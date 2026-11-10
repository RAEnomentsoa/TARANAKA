import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/security/security_question.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('sign-up asks a secret question; "Code oublié ?" checks it, then a new code, data kept', (
    tester,
  ) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tapKey(tester, 'lang-fr');
    await tapKey(tester, 'welcome-start');
    await tapKey(tester, 'type-personal');
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Lalao');
    await tapKey(tester, 'name-continue');

    // The secret question step: explained, and required.
    expect(find.text('Votre question secrète'), findsOneWidget);
    await tapKey(tester, 'secret-continue');
    expect(find.text('Choisissez une question secrète.'), findsOneWidget);
    expect(find.text("Écrivez une réponse d'au moins 2 lettres."), findsOneWidget);
    expect(find.text('Créez votre code secret à 4 chiffres'), findsNothing);

    // The list of predefined questions.
    await tapKey(tester, 'secret-question');
    expect(find.text('Quel est le nom de votre premier animal ?'), findsWidgets);
    expect(find.text('Quel est le nom de votre école primaire ?'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('secret-question-firstPet')).last);
    await settle(tester);

    // The answer typed twice: a typo is caught now, not at the recovery.
    await typeKey(tester, 'secret-answer', 'Bobby');
    await typeKey(tester, 'secret-answer-confirm', 'Boby');
    await tapKey(tester, 'secret-continue');
    expect(find.text('Les deux réponses ne sont pas identiques. Écrivez-les à nouveau.'), findsOneWidget);
    // Capitals and spaces do not count.
    await typeKey(tester, 'secret-answer-confirm', ' bobby ');
    await tapKey(tester, 'secret-continue');
    expect(find.text('Créez votre code secret à 4 chiffres'), findsOneWidget);

    // Back from the PIN: the question and answer are still there.
    await tester.tap(find.byTooltip('Retour'));
    await settle(tester);
    expect(find.text('Quel est le nom de votre premier animal ?'), findsWidgets);
    await tapKey(tester, 'secret-continue');

    await enterPin(tester, '2580');
    await enterPin(tester, '2580');
    // The key derivation and the new encrypted database take real time.
    await settleUntil(tester, () => session.stage != SessionStage.createFirstProfile);
    expect(session.stage, SessionStage.consent);
    final profile = session.profiles.single;
    expect(profile.hasRecovery, isTrue);
    expect(profile.recoveryQuestion, SecurityQuestion.firstPet.stored);
    // The answer itself is never kept.
    expect(profile.toJson().toString().toLowerCase(), isNot(contains('bobby')));

    await tapKey(tester, 'consent-accept');
    await tester.runAsync(() async {
      await session.active!.db.setMeta('test', 'gardé');
      await session.lock();
    });
    await settle(tester);

    // "Code oublié ?": the secret question first (works without Internet),
    // shown in the language of the moment.
    await tapKey(tester, 'profile-${profile.id}');
    await tapKey(tester, 'forgot-pin');
    expect(find.text('Avec ma question secrète'), findsOneWidget);
    expect(find.text('Sans Internet : Quel est le nom de votre premier animal ?'), findsOneWidget);
    await tapKey(tester, 'forgot-with-question');

    // A wrong answer is said at once, before any new code is asked.
    await typeKey(tester, 'recovery-answer-input', 'Rex');
    await tapKey(tester, 'recovery-continue');
    expect(find.text('Réponse incorrecte.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-1')), findsNothing);

    await typeKey(tester, 'recovery-answer-input', 'BOBBY');
    await tapKey(tester, 'recovery-continue');
    expect(find.text('Créez votre code secret à 4 chiffres'), findsOneWidget);
    await enterPin(tester, '9999');
    await enterPin(tester, '9999');
    expect(session.stage, SessionStage.unlocked);
    expect(await tester.runAsync(() => session.active!.db.getMeta('test')), 'gardé');
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('Paramètres: an older profile adds its secret question after its current code', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
    });
    await settle(tester);

    await tapKey(tester, 'open-settings');
    expect(find.text('Non définie : à ajouter pour ne pas perdre vos données'), findsOneWidget);
    await tapKey(tester, 'settings-secret-question');

    // The current code first.
    await enterPin(tester, '0000');
    // Nothing chosen: said under the fields.
    await tapKey(tester, 'secret-question-save');
    expect(find.text('Choisissez une question secrète.'), findsOneWidget);
    await answerFormFor(tester, 'childhoodNickname', 'Koto');
    await tapKey(tester, 'secret-question-save');
    expect(find.text('Code incorrect.'), findsWidgets);
    expect(session.active!.info.hasRecovery, isFalse);

    await enterPin(tester, '1234');
    await answerFormFor(tester, 'childhoodNickname', 'Koto');
    await tapKey(tester, 'secret-question-save');
    expect(find.text('Question secrète enregistrée.'), findsOneWidget);
    expect(session.active!.info.hasRecovery, isTrue);
    expect(find.text('Activée : fonctionne sans Internet'), findsOneWidget);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}

Future<void> answerFormFor(WidgetTester tester, String question, String answer) async {
  await tapKey(tester, 'secret-question');
  await tester.tap(find.byKey(ValueKey('secret-question-$question')).last);
  await settle(tester);
  await typeKey(tester, 'secret-answer', answer);
  await typeKey(tester, 'secret-answer-confirm', answer);
}
