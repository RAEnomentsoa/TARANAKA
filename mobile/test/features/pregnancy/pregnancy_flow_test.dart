import 'package:flutter/cupertino.dart';
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
    expect(tester.widget<Text>(find.byKey(const ValueKey('movements-count'))).data, '2');
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

  Future<void> scrollWheel(WidgetTester tester, int wheel, int items) async {
    await tester.drag(find.byType(CupertinoPicker).at(wheel), Offset(0, -48.0 * items), warnIfMissed: false);
    await settle(tester);
  }

  testWidgets('each movement is noted with its type, date and time', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 30 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-movements');
    await tapKey(tester, 'movement-type-hoquet');
    await tapKey(tester, 'movements-add');
    expect(tester.widget<Text>(find.byKey(const ValueKey('movements-count'))).data, '1');

    // A movement felt yesterday evening.
    await tapKey(tester, 'movement-type-coup_pied');
    await tapKey(tester, 'movement-when');
    await scrollWheel(tester, 0, -1); // 4 → 3 November
    await scrollWheel(tester, 3, -1); // 09 → 08 h
    await tapKey(tester, 'date-wheel-ok');
    await tapKey(tester, 'movements-add');
    final events = await tester.runAsync(() async {
      final repo = PregnancyRepository(session.active!.db, clock: env.clock);
      return repo.movementEvents((await repo.current())!.id);
    });
    expect(events!.map((e) => (e.type, e.at)), [
      (MovementType.hiccup, DateTime(2026, 11, 4, 9)),
      (MovementType.kick, DateTime(2026, 11, 3, 8)),
    ]);
    expect(tester.widget<Text>(await revealKey(tester, 'movements-count')).data, '1');
    await finish(tester, env, session);
  });

  testWidgets('follow-up: blood pressure and weight on a chosen date; high pressure gives advice', (
    tester,
  ) async {
    final (env, session) = await start(tester, daysSinceLmp: 30 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-followup');
    await tapKey(tester, 'followup-date');
    await scrollWheel(tester, 0, -2); // 4 → 2 November
    await tapKey(tester, 'date-wheel-ok');
    await typeKey(tester, 'followup-weight', '64,5');
    await tapKey(tester, 'param-bloodPressure');
    await typeKey(tester, 'followup-bp-sys', '150');
    await typeKey(tester, 'followup-bp-dia', '95');
    await tapKey(tester, 'followup-add');
    expect(find.byKey(const ValueKey('followup-advice')), findsOneWidget);
    expect(find.textContaining('Tension élevée (150/95 mmHg)'), findsOneWidget);

    final entries = await tester.runAsync(() async {
      final repo = PregnancyRepository(session.active!.db);
      return repo.followUps((await repo.current())!.id);
    });
    final e = entries!.single;
    expect(e.date, DateTime(2026, 11, 2));
    expect(e.weightKg, 64.5);
    expect((e.systolic, e.diastolic), (150, 95));
    await finish(tester, env, session);
  });

  testWidgets('follow-up: a lower pressure above the upper one is refused', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 30 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-followup');
    await tapKey(tester, 'param-bloodPressure');
    await typeKey(tester, 'followup-bp-sys', '80');
    await typeKey(tester, 'followup-bp-dia', '120');
    await tapKey(tester, 'followup-add');
    expect(find.text('La tension basse doit être plus petite que la tension haute.'), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('a past due date can be entered: the follow-up is dated from it', (tester) async {
    final env = await TestEnv.create(network: FakeNetworkStatus(NetworkKind.none));
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Lalao', pin: '1234', mode: ProfileMode.personal);
    });
    await settle(tester);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'dating-due');
    await tapKey(tester, 'due-field');
    await tapKey(tester, 'date-wheel-today');
    await tapKey(tester, 'due-field');
    await scrollWheel(tester, 0, -3); // today → 3 days ago: a past DPA
    await tapKey(tester, 'date-wheel-ok');
    await tapKey(tester, 'pregnancy-save');
    expect(find.text('40 SA + 3 j'), findsOneWidget);
    expect(find.text("Date probable d'accouchement : 01/11/2026"), findsOneWidget);
    expect(find.byKey(const ValueKey('due-passed')), findsOneWidget);
    final p = await tester.runAsync(() => PregnancyRepository(session.active!.db).current());
    expect(p!.dates.dueOn, DateTime(2026, 11, 1));
    expect(p.dueDate, DateTime(2026, 11, 1));
    await finish(tester, env, session);
  });
}
