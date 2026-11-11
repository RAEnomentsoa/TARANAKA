@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taranaka/core/db/app_database.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/core/security/pin_crypto.dart';
import 'package:taranaka/core/sync/api_client.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/core/sync/outbox.dart';
import 'package:taranaka/core/sync/sync_status.dart';
import 'package:taranaka/features/agent/data/agent_controller.dart';
import 'package:taranaka/features/agent/domain/screening.dart';

import '../helpers/test_env.dart';

/// Runs against the real Django backend loaded with `charger_demo`:
///   TARANAKA_API=http://localhost:8000 flutter test test/integration
/// Skipped when TARANAKA_API is not set.
final String? api = Platform.environment['TARANAKA_API'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // real network for this file

  late TestEnv env;
  late AppDatabase db;
  late AgentController agent;
  final web = http.Client();

  Future<String> token(String id, String pin) async {
    final r = await web.post(
      Uri.parse('$api/api/auth/login/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identifiant': id, 'pin': pin}),
    );
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(r.body) as Map)['access'] as String;
  }

  Future<Map<String, Object?>> get(String path, String access) async {
    final r = await web.get(Uri.parse('$api$path'), headers: {'Authorization': 'Bearer $access'});
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast();
  }

  setUp(() async {
    env = await TestEnv.create(apiBaseUrl: api);
    await env.services.config.load();
    db = await AppDatabase.open(
      env.services.dbOpener,
      '${env.dir.path}/agent.db',
      PinCrypto.passphrase(PinCrypto().randomBytes()),
    );
    agent = AgentController(
      services: env.services,
      database: db,
      network: FakeNetworkStatus(),
      tables: WhoTables.empty,
    );
    await agent.init();
  });

  tearDown(() async {
    agent.dispose();
    await db.close();
    env.dir.deleteSync(recursive: true);
  });

  test('scenarios 5, 7 and 8 against the real backend', () async {
    // Login as ac.rasoa: first pull brings the demo children and the centres.
    await agent.login(baseUrl: api!, identifiant: 'ac.rasoa', pin: '1234');
    expect(agent.problem, isNull, reason: agent.problemDetail);
    expect((await agent.repo.children(search: 'Soa')).isNotEmpty, isTrue);
    final crenas = (await agent.repo.centres(type: 'crenas'))
        .firstWhere((c) => c.regionId == agent.account!.user.regionId);

    // Scenario 5, offline: an 18-month-old with MUAC 112 mm (a new child, so
    // the test can be replayed on the same demo database).
    final today = DateTime.now();
    final birth = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 549));
    // D16: a child always has its mother — the demo beneficiary, opened by
    // her code (she is then followed by this agent).
    final mother = await agent.openByCode('VHG444');
    final child = await agent.repo.createChild(
      name: 'Test mobile ${today.millisecondsSinceEpoch}',
      sex: 'F',
      birthDate: birth,
      regionId: agent.account!.user.regionId,
      agentId: agent.account!.user.id,
      motherId: mother.id,
    );
    final input = ScreeningInput(
      sex: 'F',
      birthDate: birth,
      measureDate: today,
      weightKg: 8.6,
      lengthCm: 77.5,
      position: 'couche',
      muacMm: 112,
    );
    final result = ScreeningCalculator.compute(
      input,
      env.services.config.current,
      WhoTables.empty,
      today: today,
    );
    expect((result.classification, result.centre, result.urgence), ('mas', 'crenas', 'orange'));
    final m = await agent.repo.saveMeasurement(
      child: child,
      input: input,
      result: result,
      agentId: agent.account!.user.id,
    );
    final r = await agent.repo.createReferral(
      child: child,
      measurement: m,
      result: result,
      centre: crenas,
      motif: ScreeningCalculator.motif(input, result),
      agentId: agent.account!.user.id,
    );
    expect(r.transmitted, isFalse);
    final queued = await Outbox.pending(db.db);
    expect(queued.length, 3);

    // Back online: everything is acknowledged.
    final report = (await agent.syncNow())!;
    expect(report.errors, isEmpty);
    expect(report.applied, 3);
    final sent = (await agent.repo.referral(r.id))!;
    expect(sent.transmitted, isTrue);
    expect(sent.syncStatus, SyncStatus.synced);
    final serverMeasure = (await agent.repo.measurement(m.id))!;
    expect(
      (serverMeasure.classification, serverMeasure.centre, serverMeasure.urgence),
      ('mas', 'crenas', 'orange'),
      reason: 'the server re-classified with the same config',
    );

    // Scenario 7: forced resend of the same operations → no duplicate.
    final again = ApiClient(
      baseUrl: api!,
      deviceId: 'integration',
      languageCode: 'fr',
      tokens: agent.account!.tokens,
    );
    final replay = await again.push(queued.map((o) => o.toPush()).toList());
    final results = (replay['resultats']! as List).cast<Map<Object?, Object?>>();
    expect(results.every((x) => x['rejoue'] == true), isTrue);
    final nurse = await token('inf.crenas', '3333');
    final byCode = await get('/api/referrals/?code=${Uri.encodeQueryComponent(r.code)}', nurse);
    expect(byCode['count'], 1);

    // Scenario 7: concurrent change of the same record → conflict on the web.
    final admin = await token('admin.demo', '1111');
    final serverChild = await get('/api/children/${child.id}/', admin);
    final patch = await web.patch(
      Uri.parse('$api/api/children/${child.id}/'),
      headers: {'Authorization': 'Bearer $admin', 'Content-Type': 'application/json'},
      body: jsonEncode({'nom': '${child.name} (admin)', 'version': serverChild['version']}),
    );
    expect(patch.statusCode, 200, reason: patch.body);
    await agent.repo.updateChild(child.id, name: '${child.name} (téléphone)');
    final conflictReport = (await agent.syncNow())!;
    expect(conflictReport.conflicts, 1);
    expect((await agent.repo.child(child.id))!.syncStatus, SyncStatus.conflict);
    final conflicts = await get('/api/conflicts/?statut=a_verifier', nurse);
    expect(
      (conflicts['results']! as List).any((c) => (c as Map)['ligne_id'] == child.id),
      isTrue,
      reason: 'the CRENAS nurse sees the conflict',
    );

    // Scenario 8: the nurse clicks "Patient arrivé"; the agent sees it.
    final row = await get('/api/referrals/${r.id}/', nurse);
    final arrived = await web.post(
      Uri.parse('$api/api/referrals/${r.id}/status/'),
      headers: {'Authorization': 'Bearer $nurse', 'Content-Type': 'application/json'},
      body: jsonEncode({'status': 'recu', 'version': row['version']}),
    );
    expect(arrived.statusCode, 200, reason: arrived.body);
    await agent.syncNow();
    expect((await agent.repo.referral(r.id))!.status, 'recu');
  }, skip: api == null ? 'set TARANAKA_API to run against a real backend' : false);
}
