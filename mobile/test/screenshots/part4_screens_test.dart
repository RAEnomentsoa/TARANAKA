import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/util/clock.dart';
import 'package:taranaka/features/pregnancy/data/pregnancy_repository.dart';
import 'package:taranaka/features/pregnancy/domain/pregnancy.dart';

import '../helpers/config_fixture.dart';
import '../helpers/test_env.dart';
import 'screenshot_helpers.dart';

void main() {
  testWidgets('part 4 screens', (tester) async {
    await loadRealFonts();
    await setPhone(tester);
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('mg');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Lalao', pin: '1234', mode: ProfileMode.personal);
      await PregnancyRepository(
        session.active!.db,
        clock: env.clock,
      ).start(PregnancyDates(lmp: addDays(env.clock.now(), -84)), PregnancyCalculator(sampleConfig()));
    });
    await settle(tester);
    await shot(tester, '30_home_reminder_mg');
    await tapKey(tester, 'tile-pregnancy');
    await shot(tester, '31_pregnancy_mg');
    await tapKey(tester, 'pregnancy-contacts');
    await shot(tester, '32_contacts_mg');
    await tester.runAsync(session.lock);
    await settle(tester);
  }, skip: !screenshotsEnabled);
}
