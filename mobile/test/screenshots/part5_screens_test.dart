import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/util/clock.dart';
import 'package:taranaka/features/cycle/data/cycle_repository.dart';

import '../helpers/test_env.dart';
import 'screenshot_helpers.dart';

void main() {
  testWidgets('part 5 screens', (tester) async {
    await loadRealFonts();
    await setPhone(tester);
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Voahangy', pin: '1234', mode: ProfileMode.personal);
      await session.acceptConsent();
      final repo = CycleRepository(session.active!.db, clock: env.clock);
      for (final d in [
        DateTime(2026, 7, 21),
        DateTime(2026, 8, 18),
        DateTime(2026, 9, 16),
        DateTime(2026, 10, 14),
      ]) {
        await repo.end((await repo.start(d)).id, addDays(d, 4));
      }
    });
    await settle(tester);
    await tapKey(tester, 'tile-cycle');
    await shot(tester, '40_cycle');
    await tester.runAsync(session.lock);
    await settle(tester);
  }, skip: !screenshotsEnabled);
}
