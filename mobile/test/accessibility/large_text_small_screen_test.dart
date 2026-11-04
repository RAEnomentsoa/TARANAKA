import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/alerts/alert_contact.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/util/clock.dart';
import 'package:taranaka/features/child/data/child_repository.dart';
import 'package:taranaka/features/cycle/data/cycle_repository.dart';
import 'package:taranaka/features/pregnancy/data/pregnancy_repository.dart';
import 'package:taranaka/features/pregnancy/domain/pregnancy.dart';

import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/features/agent/presentation/agent_scope.dart';

import '../helpers/config_fixture.dart';
import '../helpers/fake_server.dart';
import '../helpers/test_env.dart';

/// Fails with the offending row when a layout error (overflow) happened.
void expectNoLayoutError(WidgetTester tester, String step) {
  final e = tester.takeException();
  if (e == null) return;
  final rows = <String>[];
  void visit(RenderObject o) {
    if (o is RenderFlex && o.direction == Axis.horizontal && o.hasSize) {
      var total = 0.0;
      o.visitChildren((c) => total += (c as RenderBox).hasSize ? c.size.width : 0);
      if (total > o.size.width + 0.5) {
        rows.add('${o.size.width} < $total: ${o.debugCreator.toString().split(' ← ').take(8).join(' ← ')}');
      }
    }
    o.visitChildren(visit);
  }

  visit(tester.binding.rootElement!.renderObject!);
  fail('Layout error at $step: ${e.toString().split('\n').first}\n${rows.join('\n')}');
}

/// Skill "Responsive et accessibilité": from 320 dp wide, text at 200 %.
/// Any overflow is reported by Flutter as an error and fails the test.
void main() {
  for (final lang in ['fr', 'mg']) {
    testWidgets('personal screens at 320 dp and 200 % text ($lang)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final env = await TestEnv.create();
      final session = await pumpApp(tester, env);
      late String childId;
      await tester.runAsync(() async {
        await session.setLanguage(lang);
        await session.acceptConsent();
        await session.createProfile(
          displayName: 'Voahangy Rakotomalala',
          pin: '1234',
          mode: ProfileMode.personal,
        );
        final db = session.active!.db;
        final children = ChildRepository(db, clock: env.clock);
        final c = await children.addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
        childId = c.id;
        await children.addGrowth(
          child: c,
          date: DateTime(2026, 11, 1),
          weightKg: 8.1,
          lengthCm: 70,
          position: 'couche',
          tables: WhoTables.empty,
          alerte: 'vert',
        );
        await PregnancyRepository(
          db,
          clock: env.clock,
        ).start(PregnancyDates(lmp: addDays(env.clock.now(), -84)), PregnancyCalculator(sampleConfig()));
        final cycles = CycleRepository(db, clock: env.clock);
        for (final d in [DateTime(2026, 8, 18), DateTime(2026, 9, 16), DateTime(2026, 10, 14)]) {
          await cycles.end((await cycles.start(d)).id, addDays(d, 4));
        }
        await cycles.start(DateTime(2026, 11, 3));
        await const AlertContact(centreName: 'CSB2 Ambohitsoa', centrePhone: '034 00 000 00').save(db);
      });
      await settle(tester);

      void check(String step) => expectNoLayoutError(tester, step);

      void back() => tester.state<NavigatorState>(find.byType(Navigator).first).pop();

      await tapKey(tester, 'tile-cycle');
      check('step 2');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await settle(tester);
      check('step 3');
      back();
      await settle(tester);
      check('step 4');

      await tapKey(tester, 'tile-pregnancy');
      check('step 5');
      await tapKey(tester, 'pregnancy-contacts');
      check('step 6');
      back();
      await settle(tester);
      check('step 7');
      await tapKey(tester, 'danger-saignement_vaginal');
      check('step 8');
      back();
      await settle(tester);
      check('step 9');
      back();
      await settle(tester);
      check('step 10');

      await tapKey(tester, 'tile-child');
      check('step 11');
      await tapKey(tester, 'quick-feeding-$childId');
      check('step 12');
      await tapKey(tester, 'food-vary');
      check('step 13');
      back();
      await settle(tester);
      check('step 14');
      await tapKey(tester, 'my-child-$childId');
      check('step 15');
      await tapKey(tester, 'child-growth');
      check('step 16');
      back();
      await settle(tester);
      check('step 17');
      await tapKey(tester, 'child-vaccines');
      check('step 18');
      back();
      await settle(tester);
      check('step 19');
      back();
      await settle(tester);
      check('step 20');
      back();
      await settle(tester);
      check('step 21');

      await tapKey(tester, 'open-settings');
      check('step 22');
      back();
      await settle(tester);
      check('step 23');
      await tapKey(tester, 'lock-now');
      check('step 24');
      await tapKey(tester, 'profile-${session.profiles.single.id}');
      check('step 25');
      await enterPin(tester, '1234');

      await tester.runAsync(session.lock);
      await settle(tester);
      check('step 26');
      env.dir.deleteSync(recursive: true);
    });
  }

  testWidgets('agent screens at 320 dp and 200 % text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final server = FakeServer();
    final network = FakeNetworkStatus();
    final env = await TestEnv.create(httpClient: server.client, network: network);
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('mg');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Rasoa', pin: '1234', mode: ProfileMode.agent);
    });
    await settle(tester);
    expectNoLayoutError(tester, 'login');
    await typeKey(tester, 'agent-login-id', 'ac.rasoa');
    await typeKey(tester, 'agent-login-pin', '1234');
    await tapKey(tester, 'agent-login-submit');
    expectNoLayoutError(tester, 'home');
    network.kind = NetworkKind.none;
    final agent = AgentScope.read(tester.element(await revealKey(tester, 'agent-screen')));
    await tester.runAsync(
      () => agent.repo.createChild(
        name: 'Soa Rakotomalala',
        sex: 'F',
        birthDate: DateTime(2025, 5, 4),
        regionId: 1,
        agentId: 'agent-1',
      ),
    );
    await tapKey(tester, 'agent-screen');
    expectNoLayoutError(tester, 'search');
    await tester.tap(find.text('Soa Rakotomalala'));
    await settle(tester);
    expectNoLayoutError(tester, 'child');
    await tapKey(tester, 'new-measure');
    expectNoLayoutError(tester, 'form');
    await typeKey(tester, 'field-weight', '8,6');
    await typeKey(tester, 'field-length', '77,5');
    await typeKey(tester, 'field-muac', '112');
    await tapKey(tester, 'measure-submit');
    expectNoLayoutError(tester, 'result');
    await tapKey(tester, 'create-referral');
    await tester.tap(find.byKey(const ValueKey('centre-3')));
    await settle(tester);
    expectNoLayoutError(tester, 'referral');
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
