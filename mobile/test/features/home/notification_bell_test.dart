import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/features/child/data/child_repository.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('header: bell, settings, padlock; red badge until the list is opened', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
      await session.acceptConsent();
      // 9 months on 4 Nov 2026 (the test clock), no vaccine noted: late ones.
      await ChildRepository(session.active!.db)
          .addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
    });
    await settle(tester);
    // Loads run on real async work (SQLite).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester);

    final bell = tester.getCenter(find.byKey(const ValueKey('open-notifications'))).dx;
    final settings = tester.getCenter(find.byKey(const ValueKey('open-settings'))).dx;
    final lock = tester.getCenter(find.byKey(const ValueKey('lock-now'))).dx;
    expect(bell < settings && settings < lock, isTrue);

    Badge badge() => tester.widget<Badge>(find.byKey(const ValueKey('notifications-badge')));
    expect(badge().isLabelVisible, isTrue);
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);

    await tapKey(tester, 'open-notifications');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.textContaining('Kanto'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(badge().isLabelVisible, isFalse);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
