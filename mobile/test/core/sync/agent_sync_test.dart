import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/db/app_database.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/core/security/pin_crypto.dart';
import 'package:taranaka/core/sync/api_client.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/core/sync/outbox.dart';
import 'package:taranaka/core/sync/sync_status.dart';
import 'package:taranaka/features/agent/data/agent_controller.dart';
import 'package:taranaka/features/agent/domain/models.dart';
import 'package:taranaka/features/agent/domain/screening.dart';

import '../../helpers/fake_server.dart';
import '../../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestEnv env;
  late AppDatabase db;
  late FakeServer server;
  late FakeNetworkStatus network;
  late AgentController agent;

  setUp(() async {
    env = await TestEnv.create();
    await env.services.config.load();
    db = await AppDatabase.open(
      env.services.dbOpener,
      '${env.dir.path}/agent.db',
      PinCrypto.passphrase(PinCrypto().randomBytes()),
    );
    server = FakeServer();
    network = FakeNetworkStatus();
    agent = AgentController(
      services: env.services,
      database: db,
      network: network,
      httpClient: server.client,
      tables: WhoTables.empty,
    );
    await agent.init();
  });

  tearDown(() async {
    agent.dispose();
    await db.close();
    env.dir.deleteSync(recursive: true);
  });

  Future<void> login() => agent.login(baseUrl: 'https://api.test', identifiant: 'ac.rasoa', pin: '1234');

  /// Scenario 5, offline: child, measurement MUAC 112 mm, referral.
  Future<(Child, Measurement, Referral)> screenSoa() async {
    final repo = agent.repo;
    final child = await repo.createChild(
      name: 'Soa',
      sex: 'F',
      birthDate: DateTime(2025, 5, 4),
      regionId: 1,
      agentId: 'agent-1',
      motherId: 'mere-1',
    );
    final input = ScreeningInput(
      sex: 'F',
      birthDate: child.birthDate,
      measureDate: DateTime(2026, 11, 4),
      weightKg: 8.6,
      lengthCm: 77.5,
      position: 'couche',
      muacMm: 112,
    );
    final result = ScreeningCalculator.compute(
      input,
      env.services.config.current,
      WhoTables.empty,
      today: DateTime(2026, 11, 4),
    );
    final m = await repo.saveMeasurement(child: child, input: input, result: result, agentId: 'agent-1');
    final centre = (await repo.centres(type: 'crenas')).first;
    final r = await repo.createReferral(
      child: child,
      measurement: m,
      result: result,
      centre: centre,
      motif: ScreeningCalculator.motif(input, result),
      agentId: 'agent-1',
    );
    return (child, m, r);
  }

  test('login stores the account in the encrypted profile and loads the centres', () async {
    await login();
    expect(agent.account!.user.displayName, 'Rasoa Rasoanirina');
    expect((await db.getMetaJson('agent_account'))!['refresh'], 'R1');
    expect((await agent.repo.centres()).map((c) => c.type), ['crenas', 'creni']);
    expect(agent.lastSync, isNotNull);
  });

  test('only community agent accounts can log in here', () async {
    await expectLater(
      agent.login(baseUrl: 'https://api.test', identifiant: 'inf.crenas', pin: '1234'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_agent')),
    );
    await expectLater(
      agent.login(baseUrl: 'https://api.test', identifiant: 'ac.rasoa', pin: '0000'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'identifiants_incorrects')),
    );
    expect(agent.account, isNull);
  });

  test('scenario 5 + 7: offline referral "Non transmise", then synced once back online', () async {
    await login();
    network.set(NetworkKind.none);
    final (child, m, r) = await screenSoa();
    expect(r.transmitted, isFalse);
    expect(r.syncStatus, SyncStatus.pending);
    expect(r.code, startsWith('TRK-'));
    expect(m.classification, 'mas');
    expect(await Outbox.count(db.db), 3);

    expect(await agent.syncNow(), isNull);
    expect(agent.problem, SyncProblem.offline);

    network.kind = NetworkKind.wifi;
    final report = (await agent.syncNow())!;
    expect(report.applied, 3);
    expect(server.lastPushWasGzip, isTrue);
    expect(server.lastDeviceId, isNotEmpty);
    expect(await Outbox.count(db.db), 0);
    final after = (await agent.repo.referral(r.id))!;
    expect(after.transmitted, isTrue);
    expect(after.syncStatus, SyncStatus.synced);
    expect((await agent.repo.child(child.id))!.syncStatus, SyncStatus.synced);
    // Order kept: child, then measurement, then referral.
    final ops = server.pushes.last['operations']! as List;
    expect(ops.map((o) => (o as Map)['table']), ['enfant', 'mesure', 'referencement']);
  });

  test('scenario 7: an answer lost in the network is resent without duplicates', () async {
    await login();
    await screenSoa();
    server.loseNextPushAnswer = true;
    expect(await agent.syncNow(), isNull);
    expect(agent.problem, SyncProblem.offline);
    expect(server.tables['referencement']!.length, 1, reason: 'applied once on the server');
    expect(await Outbox.count(db.db), 3, reason: 'not acknowledged: still waiting');

    final report = (await agent.syncNow())!;
    expect(report.applied, 3);
    expect(server.tables['enfant']!.length, 1);
    expect(server.tables['mesure']!.length, 1);
    expect(server.tables['referencement']!.length, 1);
    final replayed = server.pushes.last['operations']! as List;
    expect(replayed.length, 3, reason: 'same idempotency keys were resent');
  });

  test('an edit before the sync is merged into the create (one operation)', () async {
    await login();
    final c = await agent.repo.createChild(
      name: 'Sao',
      sex: 'F',
      birthDate: DateTime(2025, 5, 4),
      regionId: 1,
      agentId: 'agent-1',
      motherId: 'mere-1',
    );
    await agent.repo.updateChild(c.id, name: 'Soa');
    final ops = await Outbox.pending(db.db);
    expect(ops.length, 1);
    expect(ops.single.operation, 'create');
    expect(ops.single.payload['nom'], 'Soa');
  });

  test('two edits in a row: the second carries the version of the first', () async {
    await login();
    final c = await agent.repo.createChild(
      name: 'Soa',
      sex: 'F',
      birthDate: DateTime(2025, 5, 4),
      regionId: 1,
      agentId: 'agent-1',
      motherId: 'mere-1',
    );
    await agent.syncNow();
    await agent.repo.updateChild(c.id, name: 'Soa R.');
    await Outbox.markSending(db.db, [(await Outbox.pending(db.db)).single.seq]);
    await agent.repo.updateChild(c.id, name: 'Soa Rakoto');
    expect(await Outbox.count(db.db), 2);
    final report = (await agent.syncNow())!;
    expect(report.conflicts, 0);
    expect(server.tables['enfant']![c.id]!['nom'], 'Soa Rakoto');
    expect(server.tables['enfant']![c.id]!['version'], 3);
  });

  test('scenario 7: a concurrent change becomes a conflict, nothing is overwritten', () async {
    await login();
    final (child, _, _) = await screenSoa();
    await agent.syncNow();
    server.serverEdit('enfant', child.id, {'nom': 'Soa (corrigé au centre)'});
    await agent.repo.updateChild(child.id, name: 'Soa Rasoa');
    final report = (await agent.syncNow())!;
    expect(report.conflicts, 1);
    final local = (await agent.repo.child(child.id))!;
    expect(local.syncStatus, SyncStatus.conflict);
    expect(local.name, 'Soa Rasoa', reason: 'the pull must not overwrite an open conflict');
    expect(server.tables['enfant']![child.id]!['nom'], 'Soa (corrigé au centre)');
    expect(agent.conflicts, 1);
  });

  test('a code already used elsewhere gets a new code, the old one is kept', () async {
    await login();
    final (_, _, r) = await screenSoa();
    server.usedCodes.add(r.code);
    final report = (await agent.syncNow())!;
    expect(report.failed, 1, reason: 'refused once…');
    expect(report.applied, 3, reason: '…then resent with a new code in the same sync');
    final after = (await agent.repo.referral(r.id))!;
    expect(after.code, isNot(r.code));
    expect(after.previousCode, r.code);
    expect(after.transmitted, isTrue);
  });

  test('pull does not overwrite a row with local changes waiting', () async {
    await login();
    final (child, _, _) = await screenSoa();
    await agent.syncNow();
    await agent.repo.updateChild(child.id, name: 'Local');
    server.serverEdit('enfant', child.id, {'statut_prise_en_charge': 'pris_en_charge'});
    server.offline = true; // push fails…
    await agent.syncNow();
    expect((await agent.repo.child(child.id))!.name, 'Local');
    server.offline = false; // …next time: conflict, still not overwritten
    await agent.syncNow();
    expect((await agent.repo.child(child.id))!.name, 'Local');
  });

  test('pull applies server deletions', () async {
    await login();
    final (child, _, _) = await screenSoa();
    await agent.syncNow();
    final row = server.tables['enfant']![child.id]!;
    server.tables['enfant']![child.id] = {
      ...row,
      'deleted_at': '2026-11-05T00:00:00Z',
      'updated_at': '2026-11-05T00:00:00Z',
    };
    await agent.syncNow();
    expect(await agent.repo.child(child.id), isNull);
  });

  test('"Patient arrivé" on the web reaches the phone as "Reçu par le centre"', () async {
    await login();
    final (_, _, r) = await screenSoa();
    await agent.syncNow();
    server.serverEdit('referencement', r.id, {'status': 'recu', 'date_reception': '2026-11-04T10:00:00Z'});
    await agent.syncNow();
    final after = (await agent.repo.referral(r.id))!;
    expect(after.status, 'recu');
    expect(after.receivedAt, isNotNull);
  });

  test('an expired access token is refreshed and the new tokens are stored', () async {
    await login();
    server.expireAccessOnce = true;
    expect(await agent.syncNow(), isNotNull);
    expect(server.refreshes, 1);
    expect((await db.getMetaJson('agent_account'))!['access'], 'A2');
  });

  test('"Wi-Fi uniquement": automatic sync waits, the button still works', () async {
    await login();
    await agent.setWifiOnly(true);
    network.kind = NetworkKind.mobile;
    await screenSoa();
    expect(await agent.syncNow(), isNull);
    expect(agent.problem, SyncProblem.wifiOnly);
    expect(await agent.syncNow(manual: true), isNotNull);
    expect(agent.pending, 0);
  });

  test('a newer clinical config arrives with the pull', () async {
    final update = env.services.config.current.toJson()..['version'] = 2;
    server.configUpdate = update;
    await login();
    expect(agent.lastReport!.configUpdated, isTrue);
    expect(env.services.config.current.version, 2);
  });

  // ------------------------------------------------- beneficiaries (D16)

  test('her code (typed or from the QR) opens her file, kept for offline', () async {
    server.addBeneficiary(id: 'mere-7', prenom: 'Voahangy', code: 'K7QM4Z');
    server.tables['enfant']!['enf-1'] = {
      'id': 'enf-1',
      'mere_id': 'mere-7',
      'nom': 'Soa',
      'sexe': 'F',
      'date_naissance': '2025-05-04',
      'version': 1,
      'updated_at': '2026-11-01T08:00:00Z',
    };
    await login();
    expect(beneficiaryCodeFromScan(beneficiaryQrData('K7QM4Z')), 'K7QM4Z');
    final b = await agent.openByCode(beneficiaryQrData('k7qm4z'));
    expect(b.id, 'mere-7');
    expect(b.file, isNotNull);

    network.kind = NetworkKind.none;
    expect((await agent.repo.beneficiaries(search: 'voah')).single.id, 'mere-7');
    expect((await agent.repo.beneficiaries(search: 'K7QM')).single.id, 'mere-7');
    expect((await agent.repo.childrenOf('mere-7')).single.name, 'Soa');
  });

  test('a child screened by the agent carries mere_id (and grossesse_id)', () async {
    await login();
    final child = await agent.repo.createChild(
      name: 'Soa',
      sex: 'F',
      birthDate: DateTime(2025, 5, 4),
      regionId: 1,
      agentId: 'agent-1',
      motherId: 'mere-7',
      pregnancyId: 'gro-1',
    );
    await agent.syncNow(manual: true);
    expect(server.tables['enfant']![child.id]!['mere_id'], 'mere-7');
    expect(server.tables['enfant']![child.id]!['grossesse_id'], 'gro-1');
  });

  test('pregnant woman with a danger sign: danger + urgent referral of the pregnancy', () async {
    await login();
    final pregnancy = await agent.repo.createPregnancy(userId: 'mere-7', lmp: DateTime(2026, 8, 12));
    final centre = (await agent.repo.centres()).first;
    final r = await agent.repo.createPregnancyReferral(
      pregnancy: pregnancy,
      signs: const ['saignement_vaginal'],
      centre: centre,
      motif: 'Saignement',
      agentId: 'agent-1',
    );
    expect(await agent.repo.referralsOfPregnancy(pregnancy.id), hasLength(1));
    expect((await agent.repo.dangersOf(pregnancy.id)).single.$1, 'saignement_vaginal');

    await agent.syncNow(manual: true);
    final sent = server.tables['referencement']![r.id]!;
    expect(sent['grossesse_id'], pregnancy.id);
    expect(sent['origine'], 'grossesse');
    expect(sent['priorite'], 'urgente');
    final danger = server.tables['danger_grossesse']!.values.single;
    expect(danger['grossesse_id'], pregnancy.id);
    expect(danger['code'], 'saignement_vaginal');
    expect(server.tables['grossesse']![pregnancy.id]!['user_id'], 'mere-7');
  });
}
