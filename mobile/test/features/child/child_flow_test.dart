import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/alerts/alert_contact.dart';
import 'package:taranaka/core/alerts/red_alert_screen.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/features/child/data/child_repository.dart';

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
    expect(find.text('Allez immédiatement au centre de santé le plus proche.'), findsOneWidget);
    expect(find.text('Signe : Convulsions'), findsOneWidget);
    expect(find.text('CSB2 Ambohitsoa'), findsOneWidget);
    expect(find.text('Appeler 0340000000'), findsOneWidget);
    expect(find.text('Cette alerte ne remplace pas un diagnostic.'), findsOneWidget);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
