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
    expect(find.text('Notez au moins deux débuts de règles pour voir une prévision.'), findsOneWidget);
    await tapKey(tester, 'period-start-today');
    expect(find.text('Règles en cours depuis le 04/11/2026'), findsOneWidget);
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
}
