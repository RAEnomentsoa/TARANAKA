import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/security/profile.dart';

import '../../helpers/fake_server.dart';
import '../../helpers/test_env.dart';

void main() {
  testWidgets('scenario 1: first launch in Malagasy, offline, to the home tiles', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);

    // 1. Language
    expect(find.text('Malagasy'), findsOneWidget);
    await tapKey(tester, 'lang-mg');
    // 2. Profile type, right after the language
    expect(find.text('Manokana'), findsOneWidget);
    expect(find.text("Mpiasan'ny fahasalamana"), findsOneWidget);
    await tapKey(tester, 'type-personal');
    // 3. Consent, in Malagasy
    expect(find.text('Ny angon-drakitrao, ny safidinao'), findsOneWidget);
    await tapKey(tester, 'consent-accept');
    // 4. Profile + PIN (the mode is already chosen), then the optional
    // recovery question (skipped)
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Voahangy');
    await tapKey(tester, 'name-continue');
    await enterPin(tester, '2580');
    await enterPin(tester, '2580');
    expect(find.byKey(const ValueKey('mode-personal')), findsNothing);
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
    await tapKey(tester, 'type-personal');
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
    expect(session.stage, SessionStage.chooseProfileType);
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

  testWidgets('health worker type: straight to the account login, which creates the profile', (tester) async {
    final server = FakeServer();
    final env = await TestEnv.create(httpClient: server.client);
    final session = await pumpApp(tester, env);
    await tapKey(tester, 'lang-fr');
    expect(find.text('Personnel'), findsOneWidget);
    expect(find.text('Agent de santé'), findsOneWidget);
    await tapKey(tester, 'type-agent');
    await tapKey(tester, 'consent-accept');

    // No name nor PIN to create: the agent login, without server address.
    expect(find.text('Connexion agent de santé'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-name')), findsNothing);
    expect(find.text('Adresse du serveur'), findsNothing);
    expect(find.byKey(const ValueKey('agent-login-url')), findsNothing);

    // Back: the profile type again.
    await tester.tap(find.byTooltip('Retour'));
    await settle(tester);
    expect(session.stage, SessionStage.chooseProfileType);
    await tapKey(tester, 'type-agent');

    await typeKey(tester, 'agent-login-id', 'ac.rasoa');
    await typeKey(tester, 'agent-login-pin', '1234');
    await tapKey(tester, 'agent-login-submit');
    expect(session.stage, SessionStage.unlocked);
    expect(session.active!.info.mode, ProfileMode.agent);
    expect(session.active!.info.displayName, 'Rasoa Rasoanirina');
    expect(find.text('Dépister un enfant'), findsOneWidget);

    // The account code opens the profile on this phone.
    await tester.runAsync(session.lock);
    await settle(tester);
    await tapKey(tester, 'profile-${session.profiles.single.id}');
    await enterPin(tester, '1234');
    expect(session.stage, SessionStage.unlocked);
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('account code of 6 digits: a 4-digit code for this phone is asked once', (tester) async {
    final server = FakeServer();
    final env = await TestEnv.create(httpClient: server.client);
    final session = await pumpApp(tester, env);
    await tapKey(tester, 'lang-fr');
    await tapKey(tester, 'type-agent');
    await tapKey(tester, 'consent-accept');
    await typeKey(tester, 'agent-login-id', 'ac.rasoa');
    await typeKey(tester, 'agent-login-pin', '123456');
    await tapKey(tester, 'agent-login-submit');
    expect(
      find.text(
        "Votre code de compte n'a pas 4 chiffres. Choisissez un code à 4 chiffres pour ouvrir ce profil sur ce téléphone.",
      ),
      findsOneWidget,
    );
    await enterPin(tester, '2580');
    await enterPin(tester, '2580');
    expect(session.stage, SessionStage.unlocked);
    expect(session.active!.info.mode, ProfileMode.agent);
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('a wrong account code creates no profile', (tester) async {
    final server = FakeServer();
    final env = await TestEnv.create(httpClient: server.client);
    final session = await pumpApp(tester, env);
    await tapKey(tester, 'lang-fr');
    await tapKey(tester, 'type-agent');
    await tapKey(tester, 'consent-accept');
    await typeKey(tester, 'agent-login-id', 'ac.rasoa');
    await typeKey(tester, 'agent-login-pin', '0000');
    await tapKey(tester, 'agent-login-submit');
    expect(find.text('Connexion agent de santé'), findsOneWidget);
    expect(session.profiles, isEmpty);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('"Créer le profil" stays reachable on a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tapKey(tester, 'lang-fr');
    await tapKey(tester, 'type-personal');
    await revealKey(tester, 'consent-accept');
    await tapKey(tester, 'consent-accept');
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Hery');
    await revealKey(tester, 'name-continue');
    await tapKey(tester, 'name-continue');
    // The PIN pad scrolls too on this screen: each key is revealed first.
    for (final d in '25802580'.split('')) {
      await tapKey(tester, 'pin-$d');
    }
    await revealKey(tester, 'recovery-save');
    expect(find.text('Créer le profil'), findsOneWidget);
    await tapKey(tester, 'recovery-save');
    expect(session.stage, SessionStage.unlocked);
    expect(tester.takeException(), isNull);
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('"Ajouter un profil" starts with the profile type, then the matching creation', (tester) async {
    final env = await TestEnv.create(httpClient: FakeServer().client);
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Hery', pin: '1234', mode: ProfileMode.personal);
      await session.lock();
    });
    await settle(tester);

    await tapKey(tester, 'add-profile');
    expect(find.text('Pour moi et ma famille'), findsOneWidget);
    expect(find.text('Agent de santé'), findsOneWidget);
    expect(find.textContaining('Sans compte'), findsNothing);
    expect(find.text('Dépister, référer et suivre les enfants.'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-name')), findsNothing);

    await tapKey(tester, 'mode-agent');
    // Straight to the agent login: no name nor PIN.
    expect(find.text('Connexion agent de santé'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-name')), findsNothing);
    await typeKey(tester, 'agent-login-id', 'ac.rasoa');
    await typeKey(tester, 'agent-login-pin', '1234');
    await tapKey(tester, 'agent-login-submit');
    expect(session.stage, SessionStage.unlocked);
    expect(session.profiles.length, 2);
    expect(session.active!.info.mode, ProfileMode.agent);
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
