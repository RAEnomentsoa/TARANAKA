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

/// The logged-in professional (`utilisateur` of `/api/auth/login/`).
class ServerUser {
  const ServerUser({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.profile,
    this.regionId,
    this.csbId,
  });

  final String id;
  final String nom;
  final String prenom;
  final String profile;
  final int? regionId;
  final int? csbId;

  String get displayName => '$prenom $nom'.trim();

  Map<String, Object?> toJson() => {
    'id': id,
    'nom': nom,
    'prenom': prenom,
    'profile': profile,
    'region_id': regionId,
    'csb_id': csbId,
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
  );
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
      final bytes = utf8.encode(jsonEncode(body));
      final headers = _headers();
      if (gzipBody) headers['Content-Encoding'] = 'gzip';
      return _client.post(uri, headers: headers, body: gzipBody ? gzip.encode(bytes) : bytes);
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
