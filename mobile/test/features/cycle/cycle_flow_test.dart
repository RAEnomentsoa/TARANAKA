import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/sync/outbox.dart';
import 'package:taranaka/core/sync/sync_status.dart';
import 'package:taranaka/features/cycle/data/cycle_repository.dart';
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
    expect(find.text('Fiable'), findsOneWidget);
    expect(find.text('Vers le 11/11/2026'), findsOneWidget);
    expect(find.text('Fenêtre fertile : Du 23/10/2026 au 28/10/2026'), findsOneWidget);
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
    // First day logged: next period at +28 days.
    expect(find.text('Vers le 02/12/2026'), findsOneWidget);
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

  testWidgets('late period: suggests a pregnancy test and links to "Ma grossesse"', (tester) async {
    final (env, session) = await start(tester, [
      (DateTime(2026, 8, 1), DateTime(2026, 8, 5)),
      (DateTime(2026, 8, 29), DateTime(2026, 9, 2)),
      (DateTime(2026, 9, 26), DateTime(2026, 9, 30)),
    ]);
    await tapKey(tester, 'tile-cycle');
    expect(find.byKey(const ValueKey('signal-late')), findsOneWidget);
    expect(find.textContaining('faites un test de grossesse'), findsOneWidget);
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
    await scrollWheel(tester, 0, -1); // 4 → 3 November
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
      expect(find.text('14/10/2026'), findsOneWidget);
      expect(find.text('18/10/2026'), findsOneWidget);
      await finish(tester, env, session);
    });

    testWidgets('tapping an empty past day adds a period starting that day', (tester) async {
      final (env, session) = await start(tester, cycles);
      await tapKey(tester, 'tile-cycle');
      await revealKey(tester, 'cycle-calendar');
      await tapKey(tester, 'cal-day-2026-11-02');
      expect(find.text('02/11/2026'), findsOneWidget);
      await tapKey(tester, 'period-save');
      final periods = await tester.runAsync(() => CycleRepository(session.active!.db).periods());
      expect(periods!.map((p) => p.start), contains(DateTime(2026, 11, 2)));
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
