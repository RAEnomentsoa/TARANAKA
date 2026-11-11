import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/db/app_database.dart';
import 'package:taranaka/core/security/pin_crypto.dart';
import 'package:taranaka/core/sync/api_client.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/core/sync/outbox.dart';
import 'package:taranaka/core/util/clock.dart';
import 'package:taranaka/features/account/data/personal_sync_controller.dart';
import 'package:taranaka/features/child/data/child_repository.dart';
import 'package:taranaka/features/cycle/data/cycle_repository.dart';
import 'package:taranaka/features/pregnancy/data/pregnancy_repository.dart';
import 'package:taranaka/features/pregnancy/domain/pregnancy.dart';

import '../../helpers/config_fixture.dart';
import '../../helpers/fake_server.dart';
import '../../helpers/test_env.dart';

/// D16, personal mode: what she enters is kept on the phone first, then
/// sent once she has accepted and there is network; her account is created
/// at that first sync. The cycle is never sent unless she shares it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestEnv env;
  late AppDatabase db;
  late FakeServer server;
  late FakeNetworkStatus network;
  late PersonalSyncController sync;

  setUp(() async {
    server = FakeServer();
    network = FakeNetworkStatus()..kind = NetworkKind.none;
    env = await TestEnv.create(httpClient: server.client, network: network);
    await env.services.config.load();
    db = await AppDatabase.open(
      env.services.dbOpener,
      '${env.dir.path}/personal.db',
      PinCrypto.passphrase(PinCrypto().randomBytes()),
    );
    await PersonalSyncController.prepareRegistration(
      db,
      firstName: 'Hery',
      region: 'Analamanga',
      pin: '2580',
    );
    sync = PersonalSyncController(services: env.services, database: db, network: network);
    await sync.init();
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
    env.dir.deleteSync(recursive: true);
  });

  /// A child with a day of food, a pregnancy with a danger sign, a period.
  Future<void> enterHistory() async {
    final children = ChildRepository(db, clock: env.clock);
    final child = await children.addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
    await children.saveFeeding(
      child.child.id,
      FeedingLog(
        date: DateTime(2026, 11, 3),
        breastfeeding: 'mixte',
        foods: const {'vary', 'voanjo'},
        meals: 3,
        milkFeeds: 0,
      ),
    );
    final pregnancies = PregnancyRepository(db, clock: env.clock);
    final p = await pregnancies.start(
      PregnancyDates(lmp: addDays(env.clock.now(), -84)),
      PregnancyCalculator(sampleConfig()),
    );
    await pregnancies.recordDanger(p.id, 'saignement_vaginal', 'grossesse');
    await CycleRepository(db, clock: env.clock).start(DateTime(2026, 10, 14));
  }

  Iterable<Map<String, Object?>> pushed() =>
      server.pushes.expand((p) => (p['operations']! as List).cast<Map<String, Object?>>());

  test('offline first, then the account and the whole history at the first network', () async {
    await enterHistory();
    await sync.acceptConsent();
    expect(await sync.syncNow(), isNull);
    expect(sync.problem, PersonalSyncProblem.offline);
    expect(sync.state, PersonalSyncState.pending);
    expect(sync.account, isNull);
    expect(server.registrations, isEmpty);

    network.kind = NetworkKind.wifi;
    await sync.syncNow();
    expect(sync.problem, isNull);

    // The account: region matched by name, explicit consent, cycle private.
    final reg = server.registrations.single;
    expect(reg['prenom'], 'Hery');
    expect(reg['region_id'], 1);
    expect(reg['pin'], '2580');
    expect(reg['consentement'], isTrue);
    expect(reg['partage_cycle'], isFalse);
    expect(sync.account!.code, isNotEmpty);
    expect(sync.registration, isNull, reason: 'the PIN is not kept once the account exists');

    // Everything sent, never mere_id nor user_id (the server sets them).
    expect(sync.pending, 0);
    expect(sync.state, PersonalSyncState.synced);
    expect(await Outbox.count(db.db), 0);
    for (final op in pushed()) {
      final data = (op['donnees'] ?? const <String, Object?>{}) as Map;
      expect(data.containsKey('mere_id'), isFalse, reason: '${op['table']}');
      expect(data.containsKey('user_id'), isFalse, reason: '${op['table']}');
    }

    // The food groups of the day, computed by the phone.
    final day = server.tables['journal_alimentaire']!.values.single;
    expect(day['g1_lait_maternel'], isTrue);
    expect(day['g2_cereales_tubercules'], isTrue);
    expect(day['g3_legumineuses_noix'], isTrue);
    expect(day['g4_produits_laitiers'], isFalse);

    // The danger sign with its code and period.
    final danger = server.tables['danger_grossesse']!.values.single;
    expect(danger['code'], 'saignement_vaginal');
    expect(danger['periode'], 'grossesse');

    // The cycle stays on the phone.
    expect(pushed().where((o) => o['table'] == 'cycle' || o['table'] == 'cycle_jour'), isEmpty);
    expect(server.tables['cycle'], isEmpty);
  });

  test('no region: nothing is sent, the problem is said', () async {
    // A profile created before the region was asked.
    await PersonalSyncController.prepareRegistration(db, firstName: 'Hery', pin: '2580');
    sync.dispose();
    sync = PersonalSyncController(services: env.services, database: db, network: network);
    await sync.init();
    network.kind = NetworkKind.wifi;
    await sync.acceptConsent();
    await sync.syncNow();
    expect(sync.problem, PersonalSyncProblem.noRegion);
    expect(server.registrations, isEmpty);

    await sync.setRegion('analamanga');
    await sync.syncNow();
    expect(server.registrations.single['region_id'], 1);
  });

  test('"Partager mon cycle": on sends the cycle, off asks the server to erase it', () async {
    await enterHistory();
    network.kind = NetworkKind.wifi;
    await sync.acceptConsent();
    await sync.syncNow();
    expect(server.tables['cycle'], isEmpty);

    await sync.setCycleSharing(true);
    await sync.syncNow();
    expect(server.cycleSharingCalls, [true]);
    expect(server.tables['cycle'], hasLength(1));

    await sync.setCycleSharing(false);
    await sync.syncNow();
    expect(server.cycleSharingCalls, [true, false]);
    expect(server.tables['cycle'], isEmpty);
    // A new period stays on the phone.
    await CycleRepository(db, clock: env.clock).start(DateTime(2026, 11, 11));
    await sync.syncNow();
    expect(server.tables['cycle'], isEmpty);
  });

  test('erase "Aussi sur le serveur": the PIN is checked by the server', () async {
    network.kind = NetworkKind.wifi;
    await sync.acceptConsent();
    await sync.syncNow();
    expect(sync.account, isNotNull);

    await expectLater(
      sync.eraseOnServer('0000'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'pin_incorrect')),
    );
    expect(server.erasures, isEmpty);
    await sync.eraseOnServer('2580', includeChildren: true);
    expect(server.erasures.single['inclure_enfants'], isTrue);
  });
}
