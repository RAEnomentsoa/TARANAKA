import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.code, [this.detail]);

  /// HTTP status, or null when the server was not reached.
  final int? status;

  /// Stable code from the server (`identifiants_incorrects`, `compte_bloque`…)
  /// or a local one (`offline`, `auth_expired`, `not_agent`, `bad_response`).
  final String code;
  final String? detail;

  @override
  String toString() => 'ApiException($status, $code, $detail)';
}

class Tokens {
  const Tokens(this.access, this.refresh);
  final String access;
  final String refresh;
}

/// The logged-in user (`utilisateur` of `/api/auth/login/`): a professional,
/// or a beneficiary (D16) with her identifier and code to show the agent.
class ServerUser {
  const ServerUser({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.profile,
    this.regionId,
    this.csbId,
    this.identifiant,
    this.codeBeneficiaire,
    this.partageCycle = false,
  });

  final String id;
  final String nom;
  final String prenom;
  final String profile;
  final int? regionId;
  final int? csbId;

  /// Beneficiary: readable login (e.g. `voahangy.4821`) and short code.
  final String? identifiant;
  final String? codeBeneficiaire;
  final bool partageCycle;

  String get displayName => '$prenom $nom'.trim();

  Map<String, Object?> toJson() => {
    'id': id,
    'nom': nom,
    'prenom': prenom,
    'profile': profile,
    'region_id': regionId,
    'csb_id': csbId,
    'identifiant': identifiant,
    'code_beneficiaire': codeBeneficiaire,
    'partage_cycle': partageCycle,
  };

  factory ServerUser.fromJson(Map<String, Object?> j) => ServerUser(
    id: j['id']! as String,
    nom: (j['nom'] as String?) ?? '',
    prenom: (j['prenom'] as String?) ?? '',
    profile: j['profile'] is Map
        ? ((j['profile']! as Map)['code'] as String? ?? '')
        : (j['profile'] as String? ?? ''),
    regionId: j['region_id'] as int?,
    csbId: j['csb_id'] as int?,
    identifiant: j['identifiant'] as String?,
    codeBeneficiaire: j['code_beneficiaire'] as String?,
    partageCycle: j['partage_cycle'] == true,
  );
}

/// A region of the reference list (`/api/auth/access-request/options/`).
class ServerRegion {
  const ServerRegion(this.id, this.name);
  final int id;
  final String name;
}

/// Client of the TARANAKA API (docs/openapi.yaml). HTTPS in production;
/// request bodies of the sync are gzip-compressed (spec §9, §12).
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.deviceId,
    required this.languageCode,
    http.Client? client,
    Tokens? tokens,
    this.onTokens,
    this.timeout = const Duration(seconds: 30),
  }) : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
       _client = client ?? http.Client(),
       _tokens = tokens; // ignore: prefer_initializing_formals

  final String baseUrl;
  final String deviceId;
  final String languageCode;
  final http.Client _client;
  final Duration timeout;

  /// Called whenever the tokens change (login, rotation), to persist them.
  final FutureOr<void> Function(Tokens)? onTokens;
  Tokens? _tokens;

  Tokens? get tokens => _tokens;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers({bool auth = true, bool json = true}) => {
    'Accept': 'application/json',
    'Accept-Language': languageCode,
    'X-Device-Id': deviceId,
    if (json) 'Content-Type': 'application/json',
    if (auth && _tokens != null) 'Authorization': 'Bearer ${_tokens!.access}',
  };

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on SocketException catch (e) {
      throw ApiException(null, 'offline', e.message);
    } on TimeoutException {
      throw ApiException(null, 'offline', 'timeout');
    } on http.ClientException catch (e) {
      throw ApiException(null, 'offline', e.message);
    } on HandshakeException catch (e) {
      throw ApiException(null, 'offline', e.message);
    }
  }

  Object? _decode(http.Response r) {
    if (r.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  ApiException _error(http.Response r) {
    final body = _decode(r);
    String code = 'http_${r.statusCode}';
    String? detail;
    if (body is Map) {
      code = (body['code'] as String?) ?? code;
      detail = body['detail']?.toString() ?? body.toString();
    }
    return ApiException(r.statusCode, code, detail);
  }

  Future<(ServerUser, Tokens)> login(String identifiant, String pin) async {
    final r = await _send(
      () => _client.post(
        _uri('/api/auth/login/'),
        headers: _headers(auth: false),
        body: jsonEncode({'identifiant': identifiant, 'pin': pin}),
      ),
    );
    if (r.statusCode != 200) throw _error(r);
    final body = (_decode(r)! as Map).cast<String, Object?>();
    final tokens = Tokens(body['access']! as String, body['refresh']! as String);
    _tokens = tokens;
    await onTokens?.call(tokens);
    return (ServerUser.fromJson((body['utilisateur']! as Map).cast()), tokens);
  }

  Future<void> _refresh() async {
    final refresh = _tokens?.refresh;
    if (refresh == null) throw ApiException(401, 'auth_expired');
    final r = await _send(
      () => _client.post(
        _uri('/api/auth/refresh/'),
        headers: _headers(auth: false),
        body: jsonEncode({'refresh': refresh}),
      ),
    );
    if (r.statusCode != 200) throw ApiException(r.statusCode, 'auth_expired');
    final body = (_decode(r)! as Map).cast<String, Object?>();
    _tokens = Tokens(body['access']! as String, (body['refresh'] as String?) ?? refresh);
    await onTokens?.call(_tokens!);
  }

  /// Authorised request; refreshes the access token once on 401.
  Future<Object?> _authorised(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool gzipBody = false,
  }) async {
    Future<http.Response> once() {
      final uri = _uri(path, query);
      if (method == 'GET') return _client.get(uri, headers: _headers());
      final bytes = utf8.encode(jsonEncode(body ?? const {}));
      final headers = _headers();
      if (gzipBody) headers['Content-Encoding'] = 'gzip';
      final payload = gzipBody ? gzip.encode(bytes) : bytes;
      return method == 'PATCH'
          ? _client.patch(uri, headers: headers, body: payload)
          : _client.post(uri, headers: headers, body: payload);
    }

    var r = await _send(once);
    if (r.statusCode == 401) {
      await _refresh();
      r = await _send(once);
    }
    if (r.statusCode == 401) throw ApiException(401, 'auth_expired');
    if (r.statusCode < 200 || r.statusCode >= 300) throw _error(r);
    return _decode(r);
  }

  /// `POST /api/sync/push/`: up to 100 operations, one answer each.
  Future<Map<String, Object?>> push(List<Map<String, Object?>> operations) async =>
      ((await _authorised('POST', '/api/sync/push/', body: {'operations': operations}, gzipBody: true))!
              as Map)
          .cast();

  /// `GET /api/sync/pull/`.
  Future<Map<String, Object?>> pull({
    required List<String> tables,
    String? since,
    String? afterId,
    int? configVersion,
    int limit = 500,
  }) async =>
      ((await _authorised(
                'GET',
                '/api/sync/pull/',
                query: {
                  'tables': tables.join(','),
                  'limite': '$limit',
                  'depuis': ?since,
                  'apres_id': ?afterId,
                  if (configVersion != null) 'config_version': '$configVersion',
                },
              ))!
              as Map)
          .cast();

  Future<Map<String, Object?>> _json(Future<Object?> call) async => ((await call)! as Map).cast();

  // ------------------------------------------------------ beneficiary (D16)

  Future<void> _keep(Tokens tokens) async {
    _tokens = tokens;
    await onTokens?.call(tokens);
  }

  /// `POST /api/auth/register-beneficiary/` (public): her account, connected
  /// at once. The server chooses `identifiant` and `code_beneficiaire`.
  Future<(ServerUser, Tokens)> registerBeneficiary({
    required String prenom,
    required int regionId,
    required String pin,
    String nom = '',
    String? phone,
    bool partageCycle = false,
  }) async {
    final r = await _send(
      () => _client.post(
        _uri('/api/auth/register-beneficiary/'),
        headers: _headers(auth: false),
        body: jsonEncode({
          'prenom': prenom,
          'nom': nom,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'region_id': regionId,
          'pin': pin,
          'consentement': true,
          'partage_cycle': partageCycle,
        }),
      ),
    );
    if (r.statusCode != 201 && r.statusCode != 200) throw _error(r);
    final body = (_decode(r)! as Map).cast<String, Object?>();
    final tokens = Tokens(body['access']! as String, body['refresh']! as String);
    await _keep(tokens);
    return (ServerUser.fromJson((body['utilisateur']! as Map).cast()), tokens);
  }

  /// The regions, to match the one chosen offline (public, no account).
  Future<List<ServerRegion>> regions() async {
    final r = await _send(
      () => _client.get(_uri('/api/auth/access-request/options/'), headers: _headers(auth: false)),
    );
    if (r.statusCode != 200) throw _error(r);
    final body = (_decode(r)! as Map).cast<String, Object?>();
    return [
      for (final m in (body['regions'] as List? ?? const []).cast<Map<Object?, Object?>>())
        if (m['id'] is int && m['nom'] is String) ServerRegion(m['id']! as int, m['nom']! as String),
    ];
  }

  Future<ServerUser> me() async => ServerUser.fromJson(await _json(_authorised('GET', '/api/auth/me/')));

  /// `PATCH /api/auth/me/`: share the cycle, or stop (the server then erases it).
  Future<ServerUser> setCycleSharing(bool share) async {
    final body = await _json(_authorised('PATCH', '/api/auth/me/', body: {'partage_cycle': share}));
    return ServerUser.fromJson((body['utilisateur']! as Map).cast());
  }

  /// `POST /api/auth/changer-pin/`: the other sessions are closed, this one
  /// gets new tokens.
  Future<void> changePin(String oldPin, String newPin) async {
    final body = await _json(
      _authorised('POST', '/api/auth/changer-pin/', body: {'ancien_pin': oldPin, 'nouveau_pin': newPin}),
    );
    final access = body['access'] as String?;
    if (access != null) await _keep(Tokens(access, (body['refresh'] as String?) ?? _tokens!.refresh));
  }

  /// `POST /api/auth/my-data/erase/` (right to erasure, loi 2014-038).
  Future<Map<String, Object?>> eraseMyData(String pin, {bool includeChildren = false}) => _json(
    _authorised('POST', '/api/auth/my-data/erase/', body: {'pin': pin, 'inclure_enfants': includeChildren}),
  );

  // ------------------------------------------------------- agent (D16)

  /// `GET /api/beneficiaries/?q=`: the women of the agent's zone (no health data).
  Future<List<Map<String, Object?>>> beneficiaries({String query = ''}) async {
    final out = <Map<String, Object?>>[];
    for (var page = 1; page < 10; page++) {
      final body = await _json(
        _authorised('GET', '/api/beneficiaries/', query: {'page': '$page', if (query.isNotEmpty) 'q': query}),
      );
      out.addAll((body['results']! as List).cast<Map<Object?, Object?>>().map((m) => m.cast()));
      if (body['next'] == null) break;
    }
    return out;
  }

  /// `GET /api/beneficiaries/{id}/`: her whole file; the agent follows her.
  Future<Map<String, Object?>> beneficiary(String id) => _json(_authorised('GET', '/api/beneficiaries/$id/'));

  /// `POST /api/beneficiaries/lookup/` with the code she shows (any region).
  Future<Map<String, Object?>> lookupBeneficiary(String code) =>
      _json(_authorised('POST', '/api/beneficiaries/lookup/', body: {'code': code}));

  /// `POST /api/profiles/`: an agent registers a woman without a phone, with
  /// her consent. Identifier and code are generated by the server.
  Future<Map<String, Object?>> createBeneficiary({
    required String prenom,
    required String nom,
    required String pin,
    String? phone,
  }) => _json(
    _authorised(
      'POST',
      '/api/profiles/',
      body: {
        'prenom': prenom,
        'nom': nom,
        'pin': pin,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'consentement': true,
      },
    ),
  );

  /// `GET /api/facilities/` (all pages).
  Future<List<Map<String, Object?>>> facilities() async {
    final out = <Map<String, Object?>>[];
    for (var page = 1; page < 50; page++) {
      final body = (await _authorised('GET', '/api/facilities/', query: {'page': '$page'}))! as Map;
      out.addAll((body['results']! as List).cast<Map<Object?, Object?>>().map((m) => m.cast()));
      if (body['next'] == null) break;
    }
    return out;
  }

  void close() => _client.close();
}
