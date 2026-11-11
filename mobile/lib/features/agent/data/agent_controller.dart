import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../app/app_services.dart';
import '../../../core/db/app_database.dart';
import '../../../core/growth/who_lms.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/sync/network_status.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/models.dart';
import '../domain/referral_code.dart';
import 'agent_repository.dart';
import 'agent_sync_adapters.dart';

/// The professional account linked to this profile (stored in the encrypted
/// profile database, never elsewhere).
class AgentAccount {
  const AgentAccount({required this.baseUrl, required this.identifiant, required this.user, this.tokens});

  final String baseUrl;
  final String identifiant;
  final ServerUser user;
  final Tokens? tokens;

  Map<String, Object?> toJson() => {
    'base_url': baseUrl,
    'identifiant': identifiant,
    'user': user.toJson(),
    'access': tokens?.access,
    'refresh': tokens?.refresh,
  };

  static AgentAccount fromJson(Map<String, Object?> j) => AgentAccount(
    baseUrl: j['base_url']! as String,
    identifiant: j['identifiant']! as String,
    user: ServerUser.fromJson((j['user']! as Map).cast()),
    tokens: j['access'] == null ? null : Tokens(j['access']! as String, j['refresh']! as String),
  );

  AgentAccount withTokens(Tokens? t) =>
      AgentAccount(baseUrl: baseUrl, identifiant: identifiant, user: user, tokens: t);
}

enum SyncProblem { offline, wifiOnly, authExpired, server, notLoggedIn }

class AgentController extends ChangeNotifier {
  AgentController({
    required this.services,
    required this.database,
    required this.network,
    this.httpClient,
    WhoTables? tables,
  }) : codes = ReferralCodeGenerator(services.secrets),
       _tables = tables; // ignore: prefer_initializing_formals

  final AppServices services;
  final AppDatabase database;
  final NetworkStatus network;
  final http.Client? httpClient;
  final ReferralCodeGenerator codes;
  late final AgentRepository repo = AgentRepository(database, codes, clock: services.clock);

  static const _accountKey = 'agent_account';

  /// Stores the account in a profile database (also before its controller
  /// exists: a new agent profile created from the login).
  static Future<void> saveAccount(AppDatabase db, AgentAccount account) =>
      db.setMetaJson(_accountKey, account.toJson());
  static const _wifiOnlyKey = 'sync_wifi_only';

  WhoTables? _tables;
  WhoTables get tables => _tables ?? WhoTables.empty;

  AgentAccount? account;
  bool ready = false;
  bool syncing = false;
  bool wifiOnly = false;
  SyncProblem? problem;
  String? problemDetail;
  SyncReport? lastReport;
  DateTime? lastSync;
  int pending = 0;
  int conflicts = 0;
  StreamSubscription<NetworkKind>? _sub;
  bool _disposed = false;

  Future<void> init() async {
    final json = await database.getMetaJson(_accountKey);
    account = json == null ? null : AgentAccount.fromJson(json);
    wifiOnly = await database.getFlag(_wifiOnlyKey);
    _tables ??= await services.whoTables;
    await refreshCounts();
    ready = true;
    _notify();
    _sub = network.changes.listen((kind) {
      if (kind != NetworkKind.none && pending > 0) unawaited(syncNow());
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }

  Future<void> refreshCounts() async {
    pending = await repo.pendingCount();
    conflicts = await repo.openConflicts();
    final last = await database.getMeta('last_sync');
    lastSync = last == null ? null : DateTime.parse(last);
    _notify();
  }

  Future<String> _deviceId() => services.device.id();

  /// First login needs the network; afterwards everything works offline.
  Future<void> login({
    required String baseUrl,
    required String identifiant,
    required String pin,
    String language = 'fr',
  }) async {
    final api = ApiClient(
      baseUrl: baseUrl.trim(),
      deviceId: await _deviceId(),
      languageCode: language,
      client: httpClient,
    );
    final (user, tokens) = await api.login(identifiant.trim(), pin);
    if (user.profile != 'asc') throw ApiException(403, 'not_agent');
    final previous = account;
    if (previous != null && previous.user.id != user.id) {
      // Another person's account on this profile: refused, the data are theirs.
      throw ApiException(403, 'other_account');
    }
    account = AgentAccount(baseUrl: api.baseUrl, identifiant: identifiant.trim(), user: user, tokens: tokens);
    await saveAccount(database, account!);
    problem = null;
    _notify();
    await syncNow(manual: true);
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly = value;
    await database.setFlag(_wifiOnlyKey, value);
    _notify();
  }

  Future<ApiClient> _client({String language = 'fr'}) async {
    final a = account!;
    return ApiClient(
      baseUrl: a.baseUrl,
      deviceId: await _deviceId(),
      languageCode: language,
      client: httpClient,
      tokens: a.tokens,
      onTokens: (t) async {
        account = account!.withTokens(t);
        await database.setMetaJson(_accountKey, account!.toJson());
      },
    );
  }

  // ----------------------------------------------- beneficiaries (D16)
  //
  // Opening a file needs the network (the server records who opened it and
  // starts sending her data to this phone). Files already opened stay
  // readable offline. Each call throws [ApiException] ('offline', 404…).

  /// The women of the agent's zone, kept to be searched offline.
  Future<List<Beneficiary>> searchBeneficiaries(String query) async {
    final lines = await (await _client()).beneficiaries(query: query.trim());
    await repo.saveBeneficiaries(lines);
    return repo.beneficiaries(search: query);
  }

  /// Opens her file from the list: she is followed from now on.
  Future<Beneficiary> openBeneficiary(String id) async => _opened(await (await _client()).beneficiary(id));

  /// Opens her file with the code she shows (QR or typed), any region.
  Future<Beneficiary> openByCode(String code) async {
    final clean = beneficiaryCodeFromScan(code);
    return _opened(await (await _client()).lookupBeneficiary(clean));
  }

  Future<Beneficiary> _opened(Map<String, Object?> file) async {
    final b = await repo.saveFile(file);
    await refreshCounts();
    return b;
  }

  /// A woman without a phone, registered with her consent (cahier §3.2.A).
  /// The server generates her login and code; her file is then opened.
  Future<Beneficiary> registerBeneficiary({
    required String firstName,
    required String lastName,
    required String pin,
    String? phone,
  }) async {
    final api = await _client();
    final created = await api.createBeneficiary(
      prenom: firstName.trim(),
      nom: lastName.trim(),
      pin: pin,
      phone: phone?.trim(),
    );
    return _opened(await api.beneficiary(created['id']! as String));
  }

  /// Push the outbox, pull changes, refresh the centres. Never blocks the
  /// screens: they keep working on local data whatever happens here.
  Future<SyncReport?> syncNow({bool manual = false, String language = 'fr'}) async {
    if (syncing) return null;
    final a = account;
    if (a == null) {
      problem = SyncProblem.notLoggedIn;
      _notify();
      return null;
    }
    final kind = await network.current();
    if (kind == NetworkKind.none) {
      problem = SyncProblem.offline;
      _notify();
      return null;
    }
    if (wifiOnly && kind != NetworkKind.wifi && !manual) {
      problem = SyncProblem.wifiOnly;
      _notify();
      return null;
    }
    syncing = true;
    problem = null;
    problemDetail = null;
    _notify();
    final api = await _client(language: language);
    try {
      final engine = SyncEngine(
        database: database,
        api: api,
        adapters: agentAdapters(),
        config: services.config,
        fixers: {'referencement': referralCodeFixer(codes)},
      );
      lastReport = await engine.run();
      await repo.replaceCentres(await api.facilities());
      return lastReport;
    } on ApiException catch (e) {
      problem = switch (e.code) {
        'offline' => SyncProblem.offline,
        'auth_expired' => SyncProblem.authExpired,
        _ => SyncProblem.server,
      };
      problemDetail = e.detail ?? e.code;
      return null;
    } finally {
      syncing = false;
      await refreshCounts();
    }
  }
}

/// The code inside her QR (`TARANAKA:K7QM4Z`), or the code typed (dashes,
/// spaces and case ignored).
String beneficiaryCodeFromScan(String raw) {
  var v = raw.trim();
  final i = v.lastIndexOf(':');
  if (v.toUpperCase().startsWith('TARANAKA') && i >= 0) v = v.substring(i + 1);
  return v.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}

/// Content of the QR code shown in "Mon code".
String beneficiaryQrData(String code) => 'TARANAKA:${code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase()}';
