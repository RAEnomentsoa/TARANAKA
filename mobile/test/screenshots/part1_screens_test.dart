import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/profile.dart';

import '../helpers/test_env.dart';
import 'screenshot_helpers.dart';

void main() {
  testWidgets('part 1 screens', (tester) async {
    await loadRealFonts();
    await setPhone(tester);
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await shot(tester, '01_language');
    await tapKey(tester, 'lang-mg');
    await shot(tester, '02_profile_type_mg');
    await tapKey(tester, 'type-personal');
    await shot(tester, '02_consent_mg');
    await tapKey(tester, 'consent-accept');
    await tapKey(tester, 'name-continue');
    await shot(tester, '03_name_error');
    await tester.runAsync(() async {
      await session.createProfile(displayName: 'Voahangy', pin: '1234', mode: ProfileMode.personal);
    });
    await settle(tester);
    await shot(tester, '04_home_mg');
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.createProfile(displayName: 'Rasoa', pin: '1234', mode: ProfileMode.agent);
      await session.lock();
    });
    await settle(tester);
    await shot(tester, '05_profiles_fr');
    await tapKey(tester, 'profile-${session.profiles.first.id}');
    await enterPin(tester, '0000');
    await shot(tester, '06_unlock_wrong');
  }, skip: !screenshotsEnabled);
}
