import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/security/profile.dart';

import '../../helpers/test_env.dart';

void main() {
  testWidgets('sign-up: own secret question and answer typed once; "Code oublié ?" checks it, data kept', (
    tester,
  ) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tapKey(tester, 'lang-fr');
    await tapKey(tester, 'welcome-start');
    await tapKey(tester, 'type-personal');
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Lalao');
    await chooseRegion(tester);
    await tapKey(tester, 'name-continue');

    // The title and the exact explanation; two free fields, no list.
    expect(find.text('Votre question secrète'), findsOneWidget);
    expect(
      find.text(
        'Si vous oubliez votre code secret, cette question vous permettra de retrouver votre profil.',
      ),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<Object>), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    // Both are required.
    await tapKey(tester, 'secret-continue');
    expect(find.text('Écrivez votre question (au moins 3 lettres).'), findsOneWidget);
    expect(find.text("Écrivez une réponse d'au moins 2 lettres."), findsOneWidget);
    expect(find.text('Créez votre code secret à 4 chiffres'), findsNothing);

    // Typed once, then straight to the secret code: nothing to type again.
    await typeKey(tester, 'secret-question', 'Le nom de mon premier chien ?');
    await typeKey(tester, 'secret-answer', 'Bobby');
    await tapKey(tester, 'secret-continue');
    expect(find.text('Créez votre code secret à 4 chiffres'), findsOneWidget);

    // Back from the code: the question and answer are still there.
    await tester.tap(find.byTooltip('Retour'));
    await settle(tester);
    expect(find.text('Le nom de mon premier chien ?'), findsOneWidget);
    await tapKey(tester, 'secret-continue');

    await enterPin(tester, '2580');
    await enterPin(tester, '2580');
    await settleUntil(tester, () => session.stage != SessionStage.createFirstProfile);
    expect(session.stage, SessionStage.consent);
    final profile = session.profiles.single;
    expect(profile.hasRecovery, isTrue);
    expect(profile.recoveryQuestion, 'Le nom de mon premier chien ?');
    // The answer itself is never kept.
    expect(profile.toJson().toString().toLowerCase(), isNot(contains('bobby')));

    await agreeToConsent(tester);
    await tester.runAsync(() async {
      await session.active!.db.setMeta('test', 'gardé');
      await session.lock();
    });
    await settle(tester);

    // "Code oublié ?": her own question, first (works without Internet).
    await tapKey(tester, 'profile-${profile.id}');
    await tapKey(tester, 'forgot-pin');
    expect(find.text('Avec ma question secrète'), findsOneWidget);
    expect(find.text('Sans Internet : Le nom de mon premier chien ?'), findsOneWidget);
    await tapKey(tester, 'forgot-with-question');

    // A wrong answer is said at once, before any new code is asked.
    await typeKey(tester, 'recovery-answer-input', 'Rex');
    await tapKey(tester, 'recovery-continue');
    expect(find.text('Réponse incorrecte.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-1')), findsNothing);

    // Capitals and spaces do not count.
    await typeKey(tester, 'recovery-answer-input', ' BOBBY ');
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
      await session.acceptConsent();
    });
    await settle(tester);

    await tapKey(tester, 'open-settings');
    await revealKey(tester, 'settings-secret-question');
    expect(find.text('Non définie : à ajouter pour ne pas perdre vos données'), findsOneWidget);
    await tapKey(tester, 'settings-secret-question');

    // The current code first; a wrong one is refused.
    await enterPin(tester, '0000');
    await typeKey(tester, 'secret-question', 'Mon surnom ?');
    await typeKey(tester, 'secret-answer', 'Koto');
    await tapKey(tester, 'secret-question-save');
    expect(find.text('Code incorrect.'), findsWidgets);
    expect(session.active!.info.hasRecovery, isFalse);

    await enterPin(tester, '1234');
    await typeKey(tester, 'secret-question', 'Mon surnom ?');
    await typeKey(tester, 'secret-answer', 'Koto');
    await tapKey(tester, 'secret-question-save');
    expect(find.text('Question secrète enregistrée.'), findsOneWidget);
    expect(session.active!.info.hasRecovery, isTrue);
    expect(session.active!.info.recoveryQuestion, 'Mon surnom ?');
    expect(find.text('Activée : fonctionne sans Internet'), findsOneWidget);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
