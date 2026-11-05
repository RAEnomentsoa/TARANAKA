import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/alerts/red_alert_screen.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/core/util/clock.dart';
import 'package:taranaka/features/pregnancy/data/pregnancy_repository.dart';
import 'package:taranaka/features/pregnancy/domain/pregnancy.dart';

import '../../helpers/config_fixture.dart';
import '../../helpers/test_env.dart';

void main() {
  Future<(TestEnv, SessionController)> start(WidgetTester tester, {required int daysSinceLmp}) async {
    // Airplane mode: no network at all.
    final env = await TestEnv.create(network: FakeNetworkStatus(NetworkKind.none));
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Lalao', pin: '1234', mode: ProfileMode.personal);
      final lmp = addDays(env.clock.now(), -daysSinceLmp);
      await PregnancyRepository(
        session.active!.db,
        clock: env.clock,
      ).start(PregnancyDates(lmp: lmp), PregnancyCalculator(sampleConfig()));
    });
    await settle(tester);
    return (env, session);
  }

  Future<void> finish(WidgetTester tester, TestEnv env, SessionController session) async {
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  }

  testWidgets(
    'scenario 3: DDR D-84 → 12 SA + 0 j, due date, next ANC; "saignement" opens the alert at once',
    (tester) async {
      final (env, session) = await start(tester, daysSinceLmp: 84);
      await tapKey(tester, 'tile-pregnancy');
      expect(find.text('12 SA + 0 j'), findsOneWidget);
      expect(find.text("Date probable d'accouchement : 19/05/2027"), findsOneWidget);
      expect(find.textContaining('CPN 1 · 12 SA'), findsOneWidget);

      final watch = Stopwatch()..start();
      await tester.tap(find.byKey(const ValueKey('danger-saignement_vaginal')));
      await tester.pump(); // a single frame, no transition
      watch.stop();
      expect(find.byType(RedAlertScreen), findsOneWidget);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(find.text('Allez immédiatement au centre de santé le plus proche.'), findsOneWidget);
      expect(find.text('Signe : Saignement vaginal'), findsOneWidget);
      expect(find.text('Cette alerte ne remplace pas un diagnostic.'), findsOneWidget);
      expect(
        find.text('Ajoutez votre centre de santé et un numéro à appeler dans Paramètres.'),
        findsOneWidget,
      );

      await settle(tester);
      final dangers = await tester.runAsync(() async {
        final repo = PregnancyRepository(session.active!.db);
        return repo.dangers((await repo.current())!.id);
      });
      expect(dangers!.single.$1, 'saignement_vaginal');
      await finish(tester, env, session);
    },
  );

  testWidgets('"J\'y suis allée" marks the ANC contact', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 84);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-contacts');
    await tapKey(tester, 'contact-cpn-1');
    expect(find.text('Faite le 04/11/2026'), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('movement journal closed before 28 SA, open after', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 30 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-movements');
    expect(find.textContaining('vers 16 à 22 SA'), findsOneWidget);
    await tapKey(tester, 'movements-add');
    await tapKey(tester, 'movements-add');
    expect(find.text('2'), findsOneWidget);
    await tapKey(tester, 'movements-less');
    expect(find.byType(RedAlertScreen), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('before 28 SA there is no counter', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 20 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-movements');
    expect(find.byKey(const ValueKey('movements-add')), findsNothing);
    await finish(tester, env, session);
  });

  testWidgets('after the delivery: post-partum danger signs and postnatal contacts', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 280);
    await tester.runAsync(() async {
      final repo = PregnancyRepository(session.active!.db);
      await repo.recordDelivery((await repo.current())!.id, addDays(env.clock.now(), -2), 'exclusif');
    });
    await tapKey(tester, 'tile-pregnancy');
    expect(find.byKey(const ValueKey('danger-pertes_malodorantes')), findsOneWidget);
    expect(find.byKey(const ValueKey('danger-perte_des_eaux')), findsNothing);
    expect(find.textContaining('Consultation postnatale 2 · J3'), findsOneWidget);
    await finish(tester, env, session);
  });
}
