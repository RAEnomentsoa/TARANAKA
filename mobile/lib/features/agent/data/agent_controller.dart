import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../app/app_services.dart';
import '../../../core/db/app_database.dart';
import '../../../core/growth/who_lms.dart';
import '../../../core/growth/who_tables_loader.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/sync/network_status.dart';
import '../../../core/sync/sync_engine.dart';
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
    _tables ??= await WhoTablesLoader.load();
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
    await database.setMetaJson(_accountKey, account!.toJson());
    problem = null;
    _notify();
    await syncNow(manual: true);
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly = value;
    await database.setFlag(_wifiOnlyKey, value);
    _notify();
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
    final api = ApiClient(
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
