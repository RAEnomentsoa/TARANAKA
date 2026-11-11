import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/sync/outbox.dart';
import 'package:taranaka/core/sync/sync_status.dart';
import 'package:taranaka/features/cycle/data/cycle_repository.dart';
import 'package:taranaka/features/cycle/domain/cycle.dart';
import 'package:taranaka/features/cycle/presentation/cycle_calendar.dart';
import 'package:taranaka/features/pregnancy/presentation/pregnancy_home_screen.dart';

import '../../helpers/test_env.dart';

void main() {
  Future<(TestEnv, SessionController)> start(WidgetTester tester, List<(DateTime, DateTime?)> periods) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Voahangy', pin: '1234', mode: ProfileMode.personal);
      await session.acceptConsent();
      final repo = CycleRepository(session.active!.db, clock: env.clock);
      for (final (s, e) in periods) {
        final p = await repo.start(s);
        if (e != null) await repo.end(p.id, e);
      }
    });
    await settle(tester);
    return (env, session);
  }

  Future<void> finish(WidgetTester tester, TestEnv env, SessionController session) async {
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  }

  testWidgets('scenario 2: 3 cycles → next period and fertile window "fiable"; warning visible', (
    tester,
  ) async {
    // Today (test clock) is 4 Nov 2026.
    final (env, session) = await start(tester, [
      (DateTime(2026, 7, 21), DateTime(2026, 7, 25)),
      (DateTime(2026, 8, 18), DateTime(2026, 8, 22)), // 28
      (DateTime(2026, 9, 16), DateTime(2026, 9, 20)), // 29
      (DateTime(2026, 10, 14), DateTime(2026, 10, 18)), // 28
    ]);
    await tapKey(tester, 'tile-cycle');
    // No reliability meter any more.
    expect(find.text('Fiabilité des prévisions'), findsNothing);
    expect(find.text('Tes prochaines règles devraient arriver vers le 11/11/2026.'), findsOneWidget);
    // The countdown, very visible at the top: 7 days left.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('countdown')),
        matching: find.text('7 jours', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(find.text('avant tes prochaines règles'), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-phase-calm')), findsOneWidget);
    // No greeting in "Mon cycle" any more.
    expect(find.text('Bonjour Voahangy'), findsNothing);
    // Enough regular cycles: no wide range. No fertility card: the fertile
    // window and the ovulation are in the calendar and its legend.
    expect(find.byKey(const ValueKey('next-period-range')), findsNothing);
    expect(find.byKey(const ValueKey('fertility-card')), findsNothing);
    await revealKey(tester, 'cycle-legend');
    final legend = find.byKey(const ValueKey('cycle-legend'));
    // Just under the calendar hint.
    expect(
      tester.getTopLeft(legend).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(const ValueKey('calendar-hint'))).dy),
    );
    var previousX = double.negativeInfinity;
    var previousY = double.negativeInfinity;
    for (final (mark, label) in [
      ('period', 'Règles'),
      ('predicted', 'Règles prévues'),
      ('fertile', 'Fertile'),
      ('ovulation', 'Ovulation'),
      ('risk', 'Grossesse possible'),
    ]) {
      final name = find.descendant(of: legend, matching: find.text(label));
      expect(name, findsOneWidget);
      expect(find.byKey(ValueKey('legend-$mark')), findsOneWidget);
      // Left to right (a narrow screen continues on the next line), the
      // pictogram above its name.
      final center = tester.getCenter(name);
      expect(center.dx > previousX || center.dy > previousY, isTrue);
      previousX = center.dx;
      previousY = center.dy;
      final icon = find.descendant(
        of: find.ancestor(of: name, matching: find.byType(Column)).first,
        matching: find.byType(Icon),
      );
      expect(tester.getBottomLeft(icon).dy, lessThanOrEqualTo(tester.getTopLeft(name).dy));
    }
    // "Grossesse possible" around the next fertile window (from 19 Nov), with
    // exactly the pictogram and the colors of its legend.
    final swatch = find.descendant(of: legend, matching: find.byType(CycleSwatch));
    final legendIcon = tester.widget<Icon>(find.descendant(of: swatch, matching: find.byType(Icon)));
    final legendBox = tester.widget<Container>(find.descendant(of: swatch, matching: find.byType(Container)));
    final riskDay = find.byKey(const ValueKey('cal-day-2026-11-17'));
    final dayIcon = tester.widget<Icon>(find.descendant(of: riskDay, matching: find.byType(Icon)));
    final dayTile = tester.widget<Material>(find.ancestor(of: riskDay, matching: find.byType(Material)).first);
    expect((dayIcon.icon, dayIcon.color), (legendIcon.icon, legendIcon.color));
    expect(dayTile.color, (legendBox.decoration! as BoxDecoration).color);
    expect(
      find.text('Les prévisions sont indicatives. Elles ne sont pas une méthode de contraception fiable.'),
      findsOneWidget,
    );
    await finish(tester, env, session);
  });

  testWidgets('one tap: "mes règles ont commencé aujourd\'hui", then "terminées"', (tester) async {
    final (env, session) = await start(tester, const []);
    await tapKey(tester, 'tile-cycle');
    expect(find.byKey(const ValueKey('next-period')), findsNothing);
    await tapKey(tester, 'period-start-today');
    expect(find.text('Règles en cours depuis le 04/11/2026'), findsOneWidget);
    expect(
      find.text("C'est noté : tes règles ont commencé. Prends soin de toi aujourd'hui."),
      findsOneWidget,
    );
    expect(find.text('Jour 1 de tes règles'), findsOneWidget);
    // First day logged: next period at +28 days, with a wide range; no
    // encouragement block any more.
    expect(find.text('Tes prochaines règles devraient arriver vers le 02/12/2026.'), findsOneWidget);
    expect(find.text('Plutôt entre le 28/11/2026 et le 06/12/2026.'), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-encourage')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-goal')), findsNothing);
    await tapKey(tester, 'intensity-forte');
    await tapKey(tester, 'mood-4');
    await tapKey(tester, 'period-end-today');
    expect(find.byKey(const ValueKey('period-start-today')), findsOneWidget);

    final periods = await tester.runAsync(() => CycleRepository(session.active!.db).periods());
    expect(periods!.single.intensity, 'forte');
    expect(periods.single.mood, 4);
    expect(periods.single.length, 1);
    // Never queued for the server.
    expect(await tester.runAsync(() => Outbox.count(session.active!.db.db)), 0);
    final row = await tester.runAsync(() => session.active!.db.db.query('cycle'));
    expect(row!.single['sync_status'], SyncStatus.saved.name);
    await finish(tester, env, session);
  });

  testWidgets('"Enregistrer mon suivi du jour" saves the day; the period goes on', (tester) async {
    final (env, session) = await start(tester, [(DateTime(2026, 11, 3), null)]);
    await tapKey(tester, 'tile-cycle');
    // The three choices of an ongoing period.
    await revealKey(tester, 'day-save');
    expect(find.text('Enregistrer mon suivi du jour'), findsOneWidget);
    expect(find.text('Mes règles sont terminées aujourd\'hui'), findsOneWidget);
    expect(find.text('Choisir une autre date de fin'), findsOneWidget);
    // Every choice is explained.
    expect(find.text('Beaucoup de sang'), findsOneWidget);
    expect(find.text('Petites pertes de sang (spotting)'), findsOneWidget);
    expect(find.text('0 · Aucune'), findsOneWidget);
    expect(find.text('3 · Forte'), findsOneWidget);
    expect(find.text('Très triste, stressée ou irritable'), findsOneWidget);
    expect(find.text('Heureuse, joyeuse et pleine d\'énergie'), findsOneWidget);

    await tapKey(tester, 'intensity-moyenne');
    await tapKey(tester, 'symptom-crampes');
    await tapKey(tester, 'pain-2');
    await tapKey(tester, 'mood-2');
    await tapKey(tester, 'day-save');
    expect(find.text("C'est noté. Prends soin de toi aujourd'hui."), findsOneWidget);
    // Still ongoing: no start button.
    expect(find.byKey(const ValueKey('period-start-today')), findsNothing);

    final repo = CycleRepository(session.active!.db);
    final day = await tester.runAsync(() => repo.dayLog(DateTime(2026, 11, 4)));
    expect(day!.flow, 'moyenne');
    expect(day.pain, 2);
    expect(day.mood, 2);
    expect(day.symptoms, {'crampes'});
    final p = (await tester.runAsync(repo.periods))!.single;
    expect(p.end, isNull);
    expect(p.pain, 2);
    expect(p.symptoms, {'crampes'});

    // Last day: "Mes règles sont terminées aujourd'hui" closes the period.
    await tapKey(tester, 'period-end-today');
    expect(find.byKey(const ValueKey('period-start-today')), findsOneWidget);
    final ended = (await tester.runAsync(repo.periods))!.single;
    expect(ended.end, DateTime(2026, 11, 4));
    expect(ended.length, 2);
    await finish(tester, env, session);
  });

  testWidgets('spotting outside a period is noted without starting a period', (tester) async {
    final (env, session) = await start(tester, const []);
    await tapKey(tester, 'tile-cycle');
    await tapKey(tester, 'day-follow-up');
    // Outside a period, no real flow is offered: spotting only.
    expect(find.byKey(const ValueKey('intensity-forte')), findsNothing);
    await tapKey(tester, 'flow-spotting');
    await tapKey(tester, 'day-save');
    final repo = CycleRepository(session.active!.db);
    expect(await tester.runAsync(repo.periods), isEmpty);
    expect((await tester.runAsync(() => repo.dayLog(DateTime(2026, 11, 4))))!.isSpotting, isTrue);
    await revealKey(tester, 'day-2026-11-04');
    expect(find.text('Jours notés hors règles'), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('history: a day of an ended period is reviewed and corrected', (tester) async {
    final (env, session) = await start(tester, [(DateTime(2026, 10, 30), DateTime(2026, 11, 2))]);
    final repo = CycleRepository(session.active!.db, clock: env.clock);
    await tester.runAsync(() => repo.saveDay(DayLog(day: DateTime(2026, 10, 31), flow: 'faible', mood: 5)));
    await tapKey(tester, 'tile-cycle');
    await tapKey(tester, 'period-2026-10-30');
    // Every day of the period is listed, noted or not.
    for (final d in ['2026-10-30', '2026-10-31', '2026-11-01', '2026-11-02']) {
      await revealKey(tester, 'day-$d');
    }
    expect(find.text('Faible · Humeur : Très bien'), findsOneWidget);
    await tapKey(tester, 'day-2026-10-31');
    expect(find.text('Suivi du 31/10/2026'), findsOneWidget);
    await tapKey(tester, 'intensity-forte');
    await tapKey(tester, 'mood-1');
    await tapKey(tester, 'day-sheet-save');
    expect(find.text('Abondant · Humeur : Très mal'), findsOneWidget);

    final day = await tester.runAsync(() => repo.dayLog(DateTime(2026, 10, 31)));
    expect(day!.flow, 'forte');
    expect(day.mood, 1);
    // The period takes the heaviest flow of its days.
    expect((await tester.runAsync(repo.periods))!.single.intensity, 'forte');
    await finish(tester, env, session);
  });

  testWidgets('late period: suggests a pregnancy test and links to "Ma grossesse"', (tester) async {
    final (env, session) = await start(tester, [
      (DateTime(2026, 8, 1), DateTime(2026, 8, 5)),
      (DateTime(2026, 8, 29), DateTime(2026, 9, 2)),
      (DateTime(2026, 9, 26), DateTime(2026, 9, 30)),
    ]);
    await tapKey(tester, 'tile-cycle');
    expect(find.text('11 jours de retard'), findsOneWidget);
    await revealKey(tester, 'signal-late');
    expect(find.byKey(const ValueKey('signal-late')), findsOneWidget);
    expect(find.textContaining('fais un test de grossesse'), findsOneWidget);
    await tapKey(tester, 'go-pregnancy');
    expect(find.byType(PregnancyHomeScreen), findsOneWidget);
    await finish(tester, env, session);
  });

  Future<void> scrollWheel(WidgetTester tester, int wheel, int items) async {
    await tester.drag(find.byType(CupertinoPicker).at(wheel), Offset(0, -48.0 * items), warnIfMissed: false);
    await settle(tester);
  }

  testWidgets('a period of 3 months ago is added with its start and end date', (tester) async {
    // Today (test clock) is 4 Nov 2026.
    final (env, session) = await start(tester, const []);
    await tapKey(tester, 'tile-cycle');
    await tapKey(tester, 'period-add-past');
    await tapKey(tester, 'period-start-field');
    await scrollWheel(tester, 1, -3); // November → August
    await tapKey(tester, 'date-wheel-ok');
    expect(find.text('04/08/2026'), findsOneWidget);
    await tapKey(tester, 'period-end-field');
    // The end wheel opens 4 days after the start.
    expect(find.text('08/08/2026'), findsWidgets);
    await tapKey(tester, 'date-wheel-ok');
    await tapKey(tester, 'period-save');
    final periods = await tester.runAsync(() => CycleRepository(session.active!.db).periods());
    expect(periods!.single.start, DateTime(2026, 8, 4));
    expect(periods.single.end, DateTime(2026, 8, 8));
    await revealKey(tester, 'period-2026-08-04');
    expect(find.text('04/08/2026 – 08/08/2026 (5 j)'), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('overlapping dates are refused with a clear message', (tester) async {
    final (env, session) = await start(tester, [(DateTime(2026, 11, 1), DateTime(2026, 11, 3))]);
    await tapKey(tester, 'tile-cycle');
    await tapKey(tester, 'period-add-past');
    await tapKey(tester, 'period-start-field');
    await scrollWheel(tester, 0, -2); // 4 → 2 November
    await tapKey(tester, 'date-wheel-ok');
    await tapKey(tester, 'period-save');
    expect(find.text('Ces dates chevauchent des règles déjà notées.'), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('an ongoing period can end on another day than today', (tester) async {
    final (env, session) = await start(tester, [(DateTime(2026, 11, 1), null)]);
    await tapKey(tester, 'tile-cycle');
    await tapKey(tester, 'period-end-other-day');
    // The wheel opens on yesterday (3 November).
    await tapKey(tester, 'date-wheel-ok');
    final periods = await tester.runAsync(() => CycleRepository(session.active!.db).periods());
    expect(periods!.single.end, DateTime(2026, 11, 3));
    expect(find.byKey(const ValueKey('period-start-today')), findsOneWidget);
    await finish(tester, env, session);
  });

  testWidgets('English: the whole cycle screen is in English, configuration texts included', (tester) async {
    final (env, session) = await start(tester, const []);
    await tester.runAsync(() => session.setLanguage('en'));
    await settle(tester);
    await tapKey(tester, 'tile-cycle');
    expect(find.text('My period started today'), findsOneWidget);
    expect(
      find.text('Predictions are only indicative. They are not a reliable method of contraception.'),
      findsOneWidget,
    );
    expect(find.textContaining('règles'), findsNothing);
    expect(find.textContaining('prévisions'), findsNothing);
    await finish(tester, env, session);
  });

  group('calendar', () {
    final cycles = [
      (DateTime(2026, 7, 21), DateTime(2026, 7, 25)),
      (DateTime(2026, 8, 18), DateTime(2026, 8, 22)),
      (DateTime(2026, 9, 16), DateTime(2026, 9, 20)),
      (DateTime(2026, 10, 14), DateTime(2026, 10, 18)),
    ];

    testWidgets('a month grid: past cycles one month back, a logged period opens for correction', (
      tester,
    ) async {
      final (env, session) = await start(tester, cycles);
      await tapKey(tester, 'tile-cycle');
      await revealKey(tester, 'cycle-calendar');
      expect(find.text('Novembre 2026'), findsOneWidget);
      expect(find.text('lun'), findsOneWidget);
      await tapKey(tester, 'cal-prev');
      expect(find.text('Octobre 2026'), findsOneWidget);
      await tapKey(tester, 'cal-day-2026-10-16');
      expect(find.text('Modifier'), findsWidgets);
      // The dates in their fields (the days are also listed day by day).
      Finder inField(String key, String text) =>
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));
      expect(inField('period-start-field', '14/10/2026'), findsOneWidget);
      expect(inField('period-end-field', '18/10/2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('day-2026-10-16')), findsOneWidget);
      await finish(tester, env, session);
    });

    testWidgets('tapping an empty past day adds a period starting that day', (tester) async {
      final (env, session) = await start(tester, cycles);
      await tapKey(tester, 'tile-cycle');
      await revealKey(tester, 'cycle-calendar');
      await tapKey(tester, 'cal-day-2026-11-02');
      // First day chosen: the last one, or the usual length.
      expect(find.byKey(const ValueKey('cal-range-panel')), findsOneWidget);
      await tapKey(tester, 'cal-range-usual');
      expect(find.text('02/11/2026'), findsOneWidget);
      await tapKey(tester, 'period-save');
      final periods = await tester.runAsync(() => CycleRepository(session.active!.db).periods());
      expect(periods!.map((p) => p.start), contains(DateTime(2026, 11, 2)));
      // Started 2 days ago, usual length 5 days: may still be going on.
      expect(periods.firstWhere((p) => p.start == DateTime(2026, 11, 2)).end, isNull);
      expect(find.text("C'est noté. Tes prévisions sont à jour."), findsOneWidget);
      await finish(tester, env, session);
    });

    testWidgets('a period is chosen on the grid: first day, then last day', (tester) async {
      final (env, session) = await start(tester, cycles);
      await tapKey(tester, 'tile-cycle');
      await revealKey(tester, 'cycle-calendar');
      await tapKey(tester, 'cal-prev');
      await tapKey(tester, 'cal-day-2026-10-25');
      await tapKey(tester, 'cal-day-2026-10-28');
      Finder inField(String key, String text) =>
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));
      expect(inField('period-start-field', '25/10/2026'), findsOneWidget);
      expect(inField('period-end-field', '28/10/2026'), findsOneWidget);
      // Duration in one tap: 6 days from the 25th.
      await tapKey(tester, 'period-duration-6');
      expect(inField('period-end-field', '30/10/2026'), findsOneWidget);
      await tapKey(tester, 'period-save');
      final periods = await tester.runAsync(() => CycleRepository(session.active!.db).periods());
      final p = periods!.firstWhere((p) => p.start == DateTime(2026, 10, 25));
      expect(p.end, DateTime(2026, 10, 30));
      await finish(tester, env, session);
    });

    testWidgets('future days only show predictions and cannot be tapped; 3 months ahead at most', (
      tester,
    ) async {
      final (env, session) = await start(tester, cycles);
      await tapKey(tester, 'tile-cycle');
      await revealKey(tester, 'cycle-calendar');
      await tapKey(tester, 'cal-day-2026-11-11');
      expect(find.byKey(const ValueKey('period-save')), findsNothing);
      // What is expected that day is said under the grid.
      expect(find.text('11/11/2026 : Règles prévues · Estimé'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tapKey(tester, 'cal-next');
      }
      expect(find.text('Février 2027'), findsOneWidget);
      final next = tester.widget<IconButton>(find.byKey(const ValueKey('cal-next')));
      expect(next.onPressed, isNull);
      await tapKey(tester, 'cal-today');
      expect(find.text('Novembre 2026'), findsOneWidget);
      await finish(tester, env, session);
    });

    for (final (lang, month, weekday, legend) in [
      ('en', 'November 2026', 'Mon', 'Expected period'),
      ('mg', 'Novambra 2026', 'Alt', 'Fadim-bolana andrasana'),
    ]) {
      testWidgets('month, weekdays and legend in $lang', (tester) async {
        final (env, session) = await start(tester, cycles);
        await tester.runAsync(() => session.setLanguage(lang));
        await settle(tester);
        await tapKey(tester, 'tile-cycle');
        await revealKey(tester, 'cycle-calendar');
        expect(find.text(month), findsOneWidget);
        expect(find.text(weekday), findsOneWidget);
        expect(find.text(legend), findsOneWidget);
        await finish(tester, env, session);
      });
    }
  });
}
