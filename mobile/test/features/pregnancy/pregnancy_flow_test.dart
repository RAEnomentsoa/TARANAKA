import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show FilterChip, InputChip;
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/alerts/red_alert_screen.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/core/util/clock.dart';
import 'package:taranaka/core/widgets/status_pill.dart';
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
      await session.acceptConsent();
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

      // The signs are behind one clearly marked entry, not listed here.
      expect(find.byKey(const ValueKey('danger-saignement_vaginal')), findsNothing);
      await tapKey(tester, 'pregnancy-danger-signs');
      expect(find.text("Signes d'alerte pendant la grossesse"), findsOneWidget);

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

  testWidgets('movement journal at 30 SA; colour-coded messages', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 30 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-movements');
    // From 28 SA: a moment each day, no minimum number.
    expect(find.textContaining('30 SA : chaque jour'), findsOneWidget);
    expect(find.textContaining("Il n'y a pas de nombre minimum"), findsOneWidget);
    expect(
      find.text(
        "Votre bébé bouge moins que d'habitude ou ne bouge plus ? Contactez immédiatement une maternité.",
      ),
      findsOneWidget,
    );
    expect(find.text('Enregistrer le mouvement'), findsOneWidget);
    expect(tester.widget<NoticeBox>(find.byKey(const ValueKey('movements-info'))).tone, Tone.info);
    expect(tester.widget<NoticeBox>(find.byKey(const ValueKey('movements-tip'))).tone, Tone.caution);
    expect(tester.widget<NoticeBox>(find.byKey(const ValueKey('movements-less'))).tone, Tone.danger);
    await tapKey(tester, 'movements-add');
    await tapKey(tester, 'movements-quick');
    expect(tester.widget<Text>(find.byKey(const ValueKey('movements-count'))).data, '2');
    expect(find.text('Mouvement ressenti'), findsOneWidget);
    await tapKey(tester, 'movements-less');
    expect(find.byType(RedAlertScreen), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('before 28 SA the movements can be noted too', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 12 * 7);
    await tapKey(tester, 'tile-pregnancy');
    expect(await revealKey(tester, 'pregnancy-movements'), findsOneWidget);
    final followUp = tester.getRect(find.byKey(const ValueKey('pregnancy-followup')));
    final movements = tester.getRect(find.byKey(const ValueKey('pregnancy-movements')));
    expect(movements.top, greaterThan(followUp.bottom));
    expect(movements.top - followUp.bottom, lessThan(40));
    await tapKey(tester, 'pregnancy-movements');
    expect(find.textContaining('12 SA : il est normal de ne rien sentir encore'), findsOneWidget);
    await tapKey(tester, 'movements-add');
    expect(tester.widget<Text>(await revealKey(tester, 'movements-count')).data, '1');
    await finish(tester, env, session);
  });

  testWidgets('after the delivery: post-partum danger signs and postnatal contacts', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 280);
    await tester.runAsync(() async {
      final repo = PregnancyRepository(session.active!.db);
      await repo.recordDelivery((await repo.current())!.id, addDays(env.clock.now(), -2), 'exclusif');
    });
    await tapKey(tester, 'tile-pregnancy');
    expect(find.textContaining('Consultation postnatale 2 · J3'), findsOneWidget);
    expect(find.text("Signes d'alerte après l'accouchement"), findsOneWidget);
    await tapKey(tester, 'pregnancy-danger-signs');
    expect(find.byKey(const ValueKey('danger-pertes_malodorantes')), findsOneWidget);
    expect(find.byKey(const ValueKey('danger-perte_des_eaux')), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    // "Mouvements du bébé" stays reachable after the delivery too.
    await revealKey(tester, 'pregnancy-movements');
    expect(find.byKey(const ValueKey('pregnancy-movements')), findsOneWidget);
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
    // Hiccups are noted, not counted.
    expect(tester.widget<Text>(find.byKey(const ValueKey('movements-count'))).data, '0');
    expect(find.byKey(const ValueKey('movements-hiccups')), findsOneWidget);

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
    // Yesterday's kick is not today's count; it is in the history by day.
    expect(tester.widget<Text>(await revealKey(tester, 'movements-count')).data, '0');
    expect(await revealKey(tester, 'movement-day-2026-11-03'), findsOneWidget);
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
    expect(find.text('Mon suivi de grossesse'), findsOneWidget);
    await typeKey(tester, 'followup-weight', '64,5');
    // Blood pressure is shown by default; measured by a professional.
    await typeKey(tester, 'followup-bp-sys', '150');
    await typeKey(tester, 'followup-bp-dia', '95');
    await tapKey(tester, 'followup-source-professionnel');
    await tapKey(tester, 'followup-add');
    expect(find.byKey(const ValueKey('followup-advice')), findsOneWidget);
    expect(find.textContaining('Tension élevée (150/95 mmHg)'), findsWidgets);
    expect(find.textContaining('Reposez-vous 15 minutes'), findsOneWidget);
    // Evolution and history: the origin is shown.
    expect(await revealKey(tester, 'trend-bp'), findsOneWidget);
    expect(find.text('Un professionnel de santé'), findsWidgets);

    final entries = await tester.runAsync(() async {
      final repo = PregnancyRepository(session.active!.db);
      return repo.followUps((await repo.current())!.id);
    });
    final e = entries!.single;
    expect(e.date, DateTime(2026, 11, 2));
    expect(e.weightKg, 64.5);
    expect((e.systolic, e.diastolic), (150, 95));
    expect(e.source, MeasureSource.professional);

    // A typing mistake: corrected from the history.
    await tapKey(tester, 'followup-edit-${e.id}');
    expect(find.byKey(const ValueKey('followup-editing')), findsOneWidget);
    await typeKey(tester, 'followup-bp-sys', '125');
    await typeKey(tester, 'followup-bp-dia', '80');
    await tapKey(tester, 'followup-add');
    final corrected = await tester.runAsync(() async {
      final repo = PregnancyRepository(session.active!.db);
      return repo.followUps((await repo.current())!.id);
    });
    expect(corrected!.single.id, e.id);
    expect((corrected.single.systolic, corrected.single.diastolic), (125, 80));
    expect(corrected.single.weightKg, 64.5);
    await finish(tester, env, session);
  });

  testWidgets('"Ce que je ressens": typing filters the list; choose or add own words', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 12 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-followup');

    // "maux" keeps only "Maux de dos" and "Maux de tête", in a compact list.
    await typeKey(tester, 'followup-notes', 'maux');
    await settle(tester);
    expect(find.byKey(const ValueKey('symptom-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('symptom-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('symptom-0')), findsNothing);
    expect(find.byKey(const ValueKey('symptom-add')), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('symptom-6'))).height, lessThan(100));
    await tester.tap(find.byKey(const ValueKey('symptom-6')));
    await settle(tester);
    // "Maux de tête" is also a quick symptom: its chip is now selected.
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('quick-symptom-3'))).selected, isTrue);
    // One tap on a quick symptom: "Vision floue".
    await tapKey(tester, 'quick-symptom-4');

    // Own words: not in the list, added as they are.
    await typeKey(tester, 'followup-notes', 'Un peu stressée');
    await settle(tester);
    expect(find.text('Ajouter « Un peu stressée »'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('symptom-add')));
    await settle(tester);
    expect(find.widgetWithText(InputChip, 'Un peu stressée'), findsOneWidget);

    await tapKey(tester, 'followup-add');
    final entries = await tester.runAsync(() async {
      final repo = PregnancyRepository(session.active!.db);
      return repo.followUps((await repo.current())!.id);
    });
    expect(entries!.single.notes, 'Maux de tête, Vision floue, Un peu stressée');
    // Headache or blurred vision: pre-eclampsia signs, see someone today.
    expect(find.text("À voir aujourd'hui · Maux de tête ou vision floue"), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('follow-up: a lower pressure above the upper one is refused', (tester) async {
    final (env, session) = await start(tester, daysSinceLmp: 30 * 7);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-followup');
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
      await session.acceptConsent();
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

  testWidgets('"Mes repas": groups with local examples, count without judgement, advice, previous days', (
    tester,
  ) async {
    final (env, session) = await start(tester, daysSinceLmp: 84);
    // Yesterday: cereals, pulses, meat or fish, dark green leaves.
    await tester.runAsync(
      () => PregnancyRepository(session.active!.db).setDiet(DateTime(2026, 11, 3), {0, 1, 4, 6}),
    );
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-diet');
    expect(
      find.text(
        "Cochez les groupes d'aliments consommés aujourd'hui pour suivre la diversité de votre alimentation.",
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('women-diet-rule')), findsOneWidget);
    expect(find.text('Aucun groupe sur 10 consommé'), findsOneWidget);
    expect(find.text('Ex. : riz, manioc, patate douce, maïs, pain, etc.'), findsOneWidget);
    // No judgement on the diet.
    expect(find.text('Suffisante'), findsNothing);
    expect(find.text('Insuffisante'), findsNothing);

    await tapKey(tester, 'women-group-0');
    expect(find.text('1 groupe sur 10 consommé'), findsOneWidget);
    await revealKey(tester, 'women-diet-advice-fruitVegetable');
    expect(find.textContaining('pensez à ajouter un fruit ou un légume'), findsOneWidget);
    await tapKey(tester, 'women-group-9');
    expect(find.text('2 groupes sur 10 consommés'), findsOneWidget);
    expect(find.byKey(const ValueKey('women-diet-advice-fruitVegetable')), findsNothing);
    final saved = await tester.runAsync(
      () => PregnancyRepository(session.active!.db).dietOn(DateTime(2026, 11, 4)),
    );
    expect(saved, {0, 9});

    // Previous days: yesterday with its count; unfolds the groups eaten.
    await revealKey(tester, 'women-diet-average');
    expect(find.text('En moyenne sur les jours notés : 4,0 groupes sur 10'), findsOneWidget);
    await revealKey(tester, 'women-day-2026-11-03');
    expect(find.text('4 groupes sur 10 consommés'), findsOneWidget);
    await tapKey(tester, 'women-day-2026-11-03');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('women-day-2026-11-03')),
        matching: find.text('Brèdes et feuilles vert foncé'),
      ),
      findsOneWidget,
    );
    await finish(tester, env, session);
  });

  testWidgets('"Mes repas" at 320 dp and 200 % in Malagasy: no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final (env, session) = await start(tester, daysSinceLmp: 84);
    await tester.runAsync(() async {
      await session.setLanguage('mg');
      await PregnancyRepository(session.active!.db).setDiet(DateTime(2026, 11, 2), {0, 3, 7});
    });
    await settle(tester);
    await tapKey(tester, 'tile-pregnancy');
    await tapKey(tester, 'pregnancy-diet');
    // Large text: the count is in the list, not pinned over half the screen.
    await revealKey(tester, 'women-diet-score');
    expect(find.byKey(const ValueKey('women-diet-score')), findsOneWidget);
    await tapKey(tester, 'women-group-4');
    for (final key in [
      'women-diet-rule',
      'women-group-9',
      'women-diet-advice-fruitVegetable',
      'women-day-2026-11-02',
    ]) {
      await revealKey(tester, key);
      expect(tester.takeException(), isNull, reason: key);
    }
    await finish(tester, env, session);
  });
}
