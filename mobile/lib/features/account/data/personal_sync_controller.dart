import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/app_services.dart';
import '../../../core/db/app_database.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/sync/local_changes.dart';
import '../../../core/sync/network_status.dart';
import '../../../core/sync/outbox.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_tables.dart';
import '../../child/data/child_repository.dart';
import '../../child/domain/feeding.dart';
import '../domain/regions.dart';

/// The woman's account on the server (D16), kept in the encrypted profile
/// database only.
class BeneficiaryAccount {
  const BeneficiaryAccount({required this.baseUrl, required this.user, this.tokens});

  final String baseUrl;
  final ServerUser user;
  final Tokens? tokens;

  /// Readable login (e.g. `voahangy.4821`) and short code to show an agent.
  String get identifiant => user.identifiant ?? '';
  String get code => user.codeBeneficiaire ?? '';

  Map<String, Object?> toJson() => {
    'base_url': baseUrl,
    'user': user.toJson(),
    'access': tokens?.access,
    'refresh': tokens?.refresh,
  };

  static BeneficiaryAccount fromJson(Map<String, Object?> j) => BeneficiaryAccount(
    baseUrl: j['base_url']! as String,
    user: ServerUser.fromJson((j['user']! as Map).cast()),
    tokens: j['access'] == null ? null : Tokens(j['access']! as String, j['refresh']! as String),
  );

  BeneficiaryAccount copyWith({ServerUser? user, Tokens? tokens}) =>
      BeneficiaryAccount(baseUrl: baseUrl, user: user ?? this.user, tokens: tokens ?? this.tokens);
}

/// What the account is created with, as soon as there is network.
class PendingRegistration {
  const PendingRegistration({required this.firstName, this.region, this.phone, this.pin});

  final String firstName;

  /// Name from [madagascarRegions]; its server id is found at registration.
  final String? region;
  final String? phone;

  /// The profile PIN, kept (encrypted database) only until the account is
  /// created: it is also the PIN of the account (login from a 2nd phone).
  final String? pin;

  Map<String, Object?> toJson() => {'prenom': firstName, 'region': region, 'phone': phone, 'pin': pin};

  static PendingRegistration fromJson(Map<String, Object?> j) => PendingRegistration(
    firstName: (j['prenom'] as String?) ?? '',
    region: j['region'] as String?,
    phone: j['phone'] as String?,
    pin: j['pin'] as String?,
  );

  PendingRegistration copyWith({String? region, String? phone, String? pin}) => PendingRegistration(
    firstName: firstName,
    region: region ?? this.region,
    phone: phone ?? this.phone,
    pin: pin ?? this.pin,
  );
}

/// Sync state shown everywhere in the personal mode (spec §9): grey, orange,
/// green, red, always with an icon and a label.
enum PersonalSyncState {
  /// Grey: on this phone only (no account yet, nothing waiting).
  local,

  /// Orange: changes waiting to be sent.
  pending,

  /// Green: everything is on the server.
  synced,

  /// Red: a refusal, a conflict, or the account needs attention.
  error,
}

enum PersonalSyncProblem { offline, noPin, noRegion, regionUnknown, authExpired, server }

/// Personal mode sync (D16): account created when the network comes, consent,
/// first upload of the whole history, outbox of every module (the cycle only
/// if shared), cycle sharing, erasure on the server.
class PersonalSyncController extends ChangeNotifier {
  PersonalSyncController({required this.services, required this.database, NetworkStatus? network})
    : network = network ?? services.network;

  final AppServices services;
  final AppDatabase database;
  final NetworkStatus network;

  static const accountKey = 'compte_beneficiaire';
  static const registrationKey = 'inscription_en_attente';
  static const consentKey = 'consentement_synchro';
  static const historyKey = 'historique_envoye';
  static const _cycleToSendKey = 'partage_cycle_a_envoyer';
  static const _pinChangeKey = 'pin_serveur_en_attente';

  BeneficiaryAccount? account;
  PendingRegistration? registration;
  DateTime? consentedAt;
  bool cycleShared = false;
  bool ready = false;
  bool syncing = false;
  int pending = 0;
  int failed = 0;
  int conflicts = 0;
  DateTime? lastSync;
  PersonalSyncProblem? problem;
  String? problemDetail;
  SyncReport? lastReport;

  StreamSubscription<NetworkKind>? _sub;
  bool _disposed = false;
  Future<SyncReport?>? _running;

  bool get consented => consentedAt != null;

  PersonalSyncState get state {
    if (problem == PersonalSyncProblem.server ||
        problem == PersonalSyncProblem.authExpired ||
        problem == PersonalSyncProblem.regionUnknown ||
        failed > 0 ||
        conflicts > 0) {
      return PersonalSyncState.error;
    }
    if (pending > 0) return PersonalSyncState.pending;
    return account == null ? PersonalSyncState.local : PersonalSyncState.synced;
  }

  /// Written when the profile is created (before its home opens).
  static Future<void> prepareRegistration(
    AppDatabase db, {
    required String firstName,
    String? region,
    String? phone,
    String? pin,
  }) => db.setMetaJson(
    registrationKey,
    PendingRegistration(firstName: firstName.trim(), region: region, phone: phone?.trim(), pin: pin).toJson(),
  );

  Future<void> init() async {
    final a = await database.getMetaJson(accountKey);
    account = a == null ? null : BeneficiaryAccount.fromJson(a);
    final r = await database.getMetaJson(registrationKey);
    registration = r == null ? null : PendingRegistration.fromJson(r);
    final c = await database.getMeta(consentKey);
    consentedAt = c == null ? null : DateTime.tryParse(c);
    cycleShared = await database.getFlag(LocalChanges.cycleSharingKey);
    await refreshCounts();
    ready = true;
    _notify();
    _sub = network.changes.listen((kind) {
      if (kind != NetworkKind.none && consented && (pending > 0 || account == null)) unawaited(syncNow());
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
    if (_disposed) return;
    final db = database.db;
    try {
      pending = await Outbox.count(db);
      failed = await Outbox.failedCount(db);
      conflicts =
          (await db.rawQuery("SELECT count(*) AS n FROM conflit WHERE statut = 'a_verifier'")).first['n']!
              as int;
      final last = await database.getMeta('last_sync');
      lastSync = last == null ? null : DateTime.parse(last);
    } on DatabaseException {
      // The profile was locked meanwhile (database closed): nothing to show.
      return;
    }
    _notify();
  }

  // ----------------------------------------------------------- consent

  /// The new consent (D16) is accepted: [region] is asked of the profiles
  /// created before it. The whole local history is queued once (first launch
  /// of this version), then sent when there is network.
  Future<void> acceptConsent({String? region, String? phone, String? firstName}) async {
    final now = services.clock.now();
    var reg = registration ?? PendingRegistration(firstName: firstName ?? '');
    if (region != null || phone != null) reg = reg.copyWith(region: region, phone: phone);
    if (account == null) {
      registration = reg;
      await database.setMetaJson(registrationKey, reg.toJson());
    }
    await database.setMeta(consentKey, now.toUtc().toIso8601String());
    consentedAt = now;
    if (!await database.getFlag(historyKey)) {
      await database.db.transaction((txn) => LocalChanges.queueHistory(txn, includeCycle: cycleShared));
      await database.setFlag(historyKey, true);
    }
    await refreshCounts();
    unawaited(syncNow());
  }

  /// The PIN typed to open the profile: kept for the account while it is not
  /// created yet (profiles of an older version, opened by PIN).
  Future<void> rememberPin(String pin) async {
    final reg = registration;
    if (account != null || reg == null || reg.pin == pin) return;
    registration = reg.copyWith(pin: pin);
    await database.setMetaJson(registrationKey, registration!.toJson());
  }

  /// The profile PIN changed: the account's too (now if online, else at the
  /// next sync).
  Future<void> pinChanged(String oldPin, String newPin) async {
    if (account == null) return rememberPin(newPin);
    final waiting = await database.getMetaJson(_pinChangeKey);
    await database.setMetaJson(_pinChangeKey, {'ancien': waiting?['ancien'] ?? oldPin, 'nouveau': newPin});
    unawaited(syncNow());
  }

  /// Region chosen (or corrected) before the account exists.
  Future<void> setRegion(String region) async {
    if (account != null) return;
    registration = (registration ?? const PendingRegistration(firstName: '')).copyWith(region: region);
    await database.setMetaJson(registrationKey, registration!.toJson());
    problem = null;
    _notify();
    unawaited(syncNow());
  }

  // ------------------------------------------------------- cycle sharing

  /// "Partager mon cycle" (off by default). On: the cycle history is queued.
  /// Off: nothing of it is sent any more and the server erases its copy.
  Future<void> setCycleSharing(bool share) async {
    if (share == cycleShared) return;
    cycleShared = share;
    await database.setFlag(LocalChanges.cycleSharingKey, share);
    await database.db.transaction((txn) async {
      if (share) {
        await LocalChanges.queueHistory(txn, includeCycle: true, onlyCycle: true);
      } else {
        await LocalChanges.stopCycle(txn);
      }
    });
    if (account != null) await database.setFlag(_cycleToSendKey, share);
    await refreshCounts();
    unawaited(syncNow());
  }

  // ---------------------------------------------------------------- sync

  ApiClient _api({Tokens? tokens}) => ApiClient(
    baseUrl: account?.baseUrl ?? services.defaultApiBaseUrl,
    deviceId: _deviceId!,
    languageCode: 'fr',
    client: services.httpClient,
    tokens: tokens ?? account?.tokens,
    onTokens: (t) async {
      final a = account;
      if (a == null) return;
      account = a.copyWith(tokens: t);
      await database.setMetaJson(accountKey, account!.toJson());
    },
  );

  String? _deviceId;

  /// Creates the account if needed, sends what waits, receives the changes.
  /// Never blocks a screen: everything keeps working on local data.
  Future<SyncReport?> syncNow() {
    final running = _running;
    if (running != null) return running;
    final run = _sync().whenComplete(() => _running = null);
    _running = run;
    return run;
  }

  Future<SyncReport?> _sync() async {
    if (!consented || _disposed) return null;
    if (await network.current() == NetworkKind.none) {
      problem = PersonalSyncProblem.offline;
      _notify();
      return null;
    }
    syncing = true;
    problem = null;
    problemDetail = null;
    _notify();
    _deviceId ??= await services.device.id();
    try {
      if (account == null && !await _register()) return null;
      final api = _api();
      await _sendAccountChanges(api);
      final engine = SyncEngine(
        database: database,
        api: api,
        adapters: [
          for (final t in SyncTables.personalPull)
            if (!t.cycle || cycleShared) t.adapter,
        ],
        config: services.config,
        payloads: await _payloadBuilder(),
        phoneWins: {
          for (final t in SyncTables.personalWritable)
            if (!t.clinical) t.name,
        },
      );
      lastReport = await engine.run();
      return lastReport;
    } on ApiException catch (e) {
      problem = switch (e.code) {
        'offline' => PersonalSyncProblem.offline,
        'auth_expired' => PersonalSyncProblem.authExpired,
        _ => PersonalSyncProblem.server,
      };
      problemDetail = e.detail ?? e.code;
      return null;
    } on DatabaseException catch (e) {
      // The profile was locked meanwhile (database closed).
      debugPrint('Personal sync: $e');
      return null;
    } finally {
      syncing = false;
      await refreshCounts();
    }
  }

  /// `register-beneficiary`: needs the region (matched by name with the
  /// server's list) and the PIN.
  Future<bool> _register() async {
    final reg = registration;
    if (reg == null || reg.region == null) {
      problem = PersonalSyncProblem.noRegion;
      return false;
    }
    if (reg.pin == null) {
      problem = PersonalSyncProblem.noPin;
      return false;
    }
    final api = _api(tokens: null);
    final regionId = matchRegion(reg.region!, [for (final r in await api.regions()) (r.id, r.name)]);
    if (regionId == null) {
      problem = PersonalSyncProblem.regionUnknown;
      problemDetail = reg.region;
      return false;
    }
    final (user, tokens) = await api.registerBeneficiary(
      prenom: reg.firstName,
      regionId: regionId,
      pin: reg.pin!,
      phone: reg.phone,
      partageCycle: cycleShared,
    );
    account = BeneficiaryAccount(baseUrl: api.baseUrl, user: user, tokens: tokens);
    await database.setMetaJson(accountKey, account!.toJson());
    // The PIN is no longer kept once the account exists.
    await database.setMeta(registrationKey, null);
    registration = null;
    // Her children and pregnancies become hers on the server by themselves:
    // a beneficiary never sends mere_id nor user_id.
    _notify();
    return true;
  }

  /// Cycle sharing and PIN changed while offline.
  Future<void> _sendAccountChanges(ApiClient api) async {
    final share = await database.getMeta(_cycleToSendKey);
    if (share != null) {
      final user = await api.setCycleSharing(share == '1');
      account = account!.copyWith(user: user);
      await database.setMetaJson(accountKey, account!.toJson());
      await database.setMeta(_cycleToSendKey, null);
    }
    final pin = await database.getMetaJson(_pinChangeKey);
    if (pin != null) {
      try {
        await api.changePin(pin['ancien']! as String, pin['nouveau']! as String);
        await database.setMeta(_pinChangeKey, null);
      } on ApiException catch (e) {
        // A wrong old PIN is not retried for ever (the agent can reset it).
        if (e.status == 400) await database.setMeta(_pinChangeKey, null);
        if (e.code == 'offline') rethrow;
      }
    }
  }

  /// Payloads from the rows as they are now, with the food groups of each
  /// day (the phone knows the group of each food). The cycle is never sent
  /// unless shared.
  Future<PayloadBuilder> _payloadBuilder() async {
    final config = services.config;
    final rules = config.isLoaded
        ? FeedingRules(config.current, custom: await ChildRepository(database).customFoods())
        : null;
    final groupOf = {for (final f in rules?.foods ?? const <Food>[]) f.code: f.group};
    final ctx = PayloadContext(
      foodGroups: rules == null || rules.groups.isEmpty
          ? null
          : (foods, breastfeeding) {
              final eaten = {for (final c in foods) ?groupOf[c]};
              if (breastfeeding != 'aucun') eaten.add(rules.breastMilkGroup);
              return rules.groupFields(eaten);
            },
    );
    Future<Map<String, Object?>?> build(DatabaseExecutor db, OutboxOp op) async {
      final table = SyncTables.byName(op.table);
      if (table == null) return op.payload;
      if (table.cycle && !await LocalChanges.cycleShared(db)) return null;
      final rows = await db.query(table.name, where: 'id = ?', whereArgs: [op.rowId]);
      if (rows.isEmpty) return null;
      return table.toServer(rows.first, ctx);
    }

    return build;
  }

  // ------------------------------------------------------------- erasure

  /// "Aussi sur le serveur": `/api/auth/my-data/erase/`. Needs the network;
  /// the account is then closed by the server. Throws [ApiException].
  Future<void> eraseOnServer(String pin, {bool includeChildren = false}) async {
    if (account == null) return;
    _deviceId ??= await services.device.id();
    await _api().eraseMyData(pin, includeChildren: includeChildren);
  }
}
