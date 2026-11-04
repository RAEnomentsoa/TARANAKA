import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/security/profile.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('scenario 1: first launch in Malagasy, offline, to the home tiles', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);

    // 1. Language
    expect(find.text('Malagasy'), findsOneWidget);
    await tapKey(tester, 'lang-mg');
    // 2. Consent, in Malagasy
    expect(find.text('Ny angon-drakitrao, ny safidinao'), findsOneWidget);
    await tapKey(tester, 'consent-accept');
    // 3. Profile + PIN
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Voahangy');
    await tapKey(tester, 'name-continue');
    await enterPin(tester, '2580');
    await enterPin(tester, '2580');
    // 4. Mode, then the optional recovery question (skipped)
    await tapKey(tester, 'mode-personal');
    await tapKey(tester, 'recovery-skip');

    expect(session.stage, SessionStage.unlocked);
    expect(find.text('Manao ahoana Voahangy'), findsOneWidget);
    expect(find.text('Ny fadim-bolako'), findsOneWidget);
    expect(find.text('Ny fitondrana vohoka'), findsOneWidget);
    expect(find.text('Ny zanako'), findsOneWidget);
    expect(find.byKey(const ValueKey('config-banner')), findsOneWidget);
    expect(session.active!.info.mode, ProfileMode.personal);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('PIN mismatch asks again', (tester) async {
    final env = await TestEnv.create();
    await pumpApp(tester, env);
    await tapKey(tester, 'lang-fr');
    await tapKey(tester, 'consent-accept');
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Hery');
    await tapKey(tester, 'name-continue');
    await enterPin(tester, '1111');
    await enterPin(tester, '2222');
    expect(find.text('Les deux codes sont différents. Recommencez.'), findsOneWidget);
    expect(find.text('Choisissez un code à 4 chiffres'), findsOneWidget);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('lock, wrong PIN, right PIN; data survives', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Hery', pin: '1234', mode: ProfileMode.personal);
      await session.active!.db.setMeta('test', 'gardé');
    });
    await settle(tester);

    await tapKey(tester, 'lock-now');
    expect(session.stage, SessionStage.locked);
    expect(find.text('Hery'), findsOneWidget);

    await tapKey(tester, 'profile-${session.profiles.single.id}');
    await enterPin(tester, '0000');
    expect(find.text('Code incorrect.'), findsOneWidget);
    await enterPin(tester, '1234');
    expect(session.stage, SessionStage.unlocked);
    expect(await tester.runAsync(() => session.active!.db.getMeta('test')), 'gardé');

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('2 minutes without activity locks the app', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Hery', pin: '1234', mode: ProfileMode.personal);
    });
    await settle(tester);
    final now = DateTime.now();
    expect(await tester.runAsync(() => session.lockIfIdle(now.add(const Duration(seconds: 90)))), isFalse);
    expect(await tester.runAsync(() => session.lockIfIdle(now.add(const Duration(minutes: 3)))), isTrue);
    await settle(tester);
    expect(session.stage, SessionStage.locked);
    expect(find.text('Qui utilise le téléphone ?'), findsOneWidget);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('"Effacer toutes mes données" deletes the profile and its file', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    late String path;
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Hery', pin: '1234', mode: ProfileMode.personal);
      path = await env.services.profileDbPath(session.active!.info.id);
    });
    await settle(tester);
    expect(File(path).existsSync(), isTrue);

    await tapKey(tester, 'open-settings');
    await tapKey(tester, 'settings-erase');
    await tester.tap(find.text('Effacer'));
    await settle(tester);

    expect(File(path).existsSync(), isFalse);
    expect(session.profiles, isEmpty);
    expect(session.stage, SessionStage.createFirstProfile);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('forgotten PIN with recovery question keeps the data', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(
        displayName: 'Lalao',
        pin: '1234',
        mode: ProfileMode.personal,
        recoveryQuestion: 'Ville natale',
        recoveryAnswer: 'Ambositra',
      );
      await session.active!.db.setMeta('test', 'gardé');
      await session.lock();
    });
    await settle(tester);

    await tapKey(tester, 'profile-${session.profiles.single.id}');
    await tapKey(tester, 'forgot-pin');
    expect(find.text('Ville natale'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('recovery-answer-input')), 'ambositra');
    await tapKey(tester, 'recovery-continue');
    await enterPin(tester, '9999');
    await enterPin(tester, '9999');
    expect(session.stage, SessionStage.unlocked);
    expect(await tester.runAsync(() => session.active!.db.getMeta('test')), 'gardé');
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
