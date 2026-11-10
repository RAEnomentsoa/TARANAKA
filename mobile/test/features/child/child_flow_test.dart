import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/alerts/alert_contact.dart';
import 'package:taranaka/core/alerts/red_alert_screen.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/features/child/data/child_repository.dart';
import 'package:taranaka/features/child/domain/feeding.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('scenario 4: 9 months, vary + anana + breast milk → 3/8, advice to add an animal food', (
    tester,
  ) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    late String childId;
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
      // 9 months on 4 Nov 2026 (the test clock).
      final c = await ChildRepository(session.active!.db)
          .addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
      childId = c.id;
    });
    await settle(tester);

    // Home → Mon enfant → "Repas du jour": 2 taps, the 3rd records a food.
    await tapKey(tester, 'tile-child');
    await tapKey(tester, 'quick-feeding-$childId');
    for (final food in ['vary', 'anana', 'lait_maternel']) {
      await tapKey(tester, 'food-$food');
    }
    // The pinned summary is visible without scrolling.
    expect(find.byKey(const ValueKey('diversity-summary')), findsOneWidget);
    expect(find.text('Diversité : 3/8 groupes'), findsOneWidget);
    expect(find.text('Insuffisante'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('advice-ajouter_aliment_animal')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('advice-ajouter_aliment_animal')), findsOneWidget);
    expect(find.textContaining('œuf ou du poisson séché'), findsOneWidget);

    final saved = await tester.runAsync(
      () => ChildRepository(session.active!.db).feeding(childId, DateTime(2026, 11, 4)),
    );
    expect(saved!.foods, {'vary', 'anana', 'lait_maternel'});

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('child danger sign: red alert opens at once, offline, with call and disclaimer', (
    tester,
  ) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    late String childId;
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
      childId = (await ChildRepository(
        session.active!.db,
      ).addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1))).id;
      await const AlertContact(
        centreName: 'CSB2 Ambohitsoa',
        centrePhone: '0340000000',
      ).save(session.active!.db);
    });
    await settle(tester);
    await tapKey(tester, 'tile-child');
    await tapKey(tester, 'my-child-$childId');
    await tapKey(tester, 'child-danger');

    await tester.tap(find.byKey(const ValueKey('danger-convulsions')));
    await tester.pump(); // one frame: no animation, no waiting
    expect(find.byType(RedAlertScreen), findsOneWidget);
    expect(find.text('URGENCE : consultez immédiatement !'), findsOneWidget);
    expect(find.text('Vous avez signalé des convulsions.'), findsOneWidget);
    expect(find.text("Emmenez immédiatement l'enfant dans un centre de santé."), findsOneWidget);
    expect(find.text('CSB2 Ambohitsoa'), findsOneWidget);
    expect(find.text('Appeler mon centre de santé'), findsOneWidget);
    expect(find.text('Cette alerte ne remplace pas un diagnostic.'), findsOneWidget);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('"Noter une tétée": "Heure de la tétée" on one line at 320 dp and 200 %, time picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    late String childId;
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
      // 2 months on 4 Nov 2026: breastfeeding.
      final c = await ChildRepository(session.active!.db)
          .addChild(name: 'Kanto', sex: 'F', birthDate: DateTime(2026, 9, 4));
      childId = c.id;
    });
    await settle(tester);

    await tapKey(tester, 'tile-child');
    await tapKey(tester, 'quick-feeding-$childId');
    await tapKey(tester, 'feed-add');
    // The label on one horizontal line, never letter by letter.
    final label = find.text('Heure de la tétée');
    expect(label, findsOneWidget);
    final size = tester.getSize(label);
    expect(size.width, greaterThan(size.height * 3));
    expect(tester.takeException(), isNull);

    // The field opens the wheels; the chosen time is shown.
    await tapKey(tester, 'feed-time');
    expect(find.byKey(const ValueKey('time-wheel-ok')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'time-wheel-ok');
    expect(find.byKey(const ValueKey('time-wheel-ok')), findsNothing);
    expect(find.text('Heure de la tétée'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('Allaitement: 7-day calendar and balance, a feed corrected, advice adapted to a difficulty', (
    tester,
  ) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    late String childId;
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
      // 2 months on 4 Nov 2026 (the test clock).
      final repo = ChildRepository(session.active!.db);
      final c = await repo.addChild(name: 'Kanto', sex: 'F', birthDate: DateTime(2026, 9, 4));
      childId = c.id;
      for (final d in [DateTime(2026, 11, 1), DateTime(2026, 11, 2), DateTime(2026, 11, 3)]) {
        await repo.saveFeeding(
          childId,
          FeedingLog(date: d, breastfeeding: 'exclusif', foods: const {}, meals: 0, milkFeeds: 0),
        );
      }
      await repo.addFeed(childId, DateTime(2026, 11, 4, 8, 30), BreastFeed.atBreast, minutes: 15);
    });
    await settle(tester);
    await tapKey(tester, 'tile-child');
    await tapKey(tester, 'quick-feeding-$childId');

    // Balance in words and as a bar; the 7 days of the calendar.
    await revealKey(tester, 'bf-balance');
    expect(find.text("3 jours d'allaitement exclusif sur 7"), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('bf-progress')));
    expect(bar.value, closeTo(3 / 7, 1e-9));
    for (var day = 29; day <= 31; day++) {
      expect(find.byKey(ValueKey('bf-day-2026-10-$day')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('bf-day-2026-11-04')), findsOneWidget);

    // A feed is corrected: time and duration, not only deleted.
    final feed = (await tester.runAsync(
      () => ChildRepository(session.active!.db).feeds(childId, DateTime(2026, 11, 4)),
    ))!.single;
    await tapKey(tester, 'feed-${feed.id}');
    expect(find.text('Modifier la tétée'), findsOneWidget);
    expect(find.text('08:30'), findsOneWidget);
    await tapKey(tester, 'inc-Durée (minutes)');
    await tapKey(tester, 'feed-save');
    final edited = (await tester.runAsync(
      () => ChildRepository(session.active!.db).feeds(childId, DateTime(2026, 11, 4)),
    ))!.single;
    expect(edited.id, feed.id);
    expect(edited.minutes, 20);

    // Advice: the age first; a reported difficulty comes on top.
    await revealKey(tester, 'tip-stage_settled');
    expect(find.byKey(const ValueKey('tip-difficulty_engorgement')), findsNothing);
    await tapKey(tester, 'bf-difficulty-engorgement');
    await revealKey(tester, 'tip-difficulty_engorgement');
    expect(find.text('Seins durs et gonflés'), findsWidgets);
    final saved = await tester.runAsync(
      () => ChildRepository(session.active!.db).breastfeedingDifficultiesOf(childId),
    );
    expect(saved, {'engorgement'});

    // Positions with a pictogram, in pale yellow boxes.
    await revealKey(tester, 'position-rugby');
    expect(find.text('Ballon de rugby'), findsOneWidget);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('Allaitement at 320 dp and 200 %: calendar, advice and positions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    late String childId;
    await tester.runAsync(() async {
      await session.setLanguage('mg');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
      final c = await ChildRepository(session.active!.db)
          .addChild(name: 'Kanto', sex: 'F', birthDate: DateTime(2026, 11, 1));
      childId = c.id;
      await ChildRepository(session.active!.db).setBreastfeedingDifficulties(childId, {'douleur'});
    });
    await settle(tester);
    await tapKey(tester, 'tile-child');
    await tapKey(tester, 'quick-feeding-$childId');
    for (final key in [
      'bf-balance',
      'bf-day-2026-10-29',
      'bf-difficulties',
      'tip-difficulty_douleur',
      'tip-stage_firstWeek',
      'position-side',
      'tip-enough',
    ]) {
      await revealKey(tester, key);
      expect(tester.takeException(), isNull, reason: key);
    }

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
