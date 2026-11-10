import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/auth/auth_service.dart';
import 'package:taranaka/core/i18n/fallback_localizations.dart';
import 'package:taranaka/core/i18n/l10n.dart';
import 'package:taranaka/features/profiles/presentation/email_link_form.dart';

/// "Code oublié ?" by e-mail: send the standard Firebase link, then type the
/// password chosen on its page. No database, no network.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Future<AuthResult<void>> Function() onSend,
    required Future<AuthError?> Function(String) onSubmit,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, ...frameworkDelegates],
      home: Scaffold(
        body: SingleChildScrollView(
          child: EmailLinkForm(
            help: 'aide',
            sentTo: maskEmail('hery@exemple.mg'),
            submitLabel: 'Continuer',
            onSend: onSend,
            onSubmit: onSubmit,
          ),
        ),
      ),
    ),
  );

  test('the address is masked on locked screens', () {
    expect(maskEmail('hery@exemple.mg'), 'h***@exemple.mg');
    expect(maskEmail('pas-une-adresse'), 'pas-une-adresse');
  });

  testWidgets('send the link, then a wrong and a right password', (tester) async {
    var sent = 0;
    final typed = <String>[];
    await pump(
      tester,
      onSend: () async {
        sent++;
        return const AuthResult.ok(null);
      },
      onSubmit: (password) async {
        typed.add(password);
        return password == 'bon' ? null : AuthError.wrongPassword;
      },
    );
    expect(find.byKey(const ValueKey('email-password')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('email-send')));
    await tester.pumpAndSettle();
    expect(sent, 1);
    expect(
      find.text('E-mail envoyé à h***@exemple.mg. Regardez aussi dans les courriers indésirables (spam).'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const ValueKey('email-password')), 'mauvais');
    await tester.tap(find.byKey(const ValueKey('email-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text("Mot de passe incorrect. Tapez celui que vous avez choisi avec le lien de l'e-mail."),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const ValueKey('email-password')), 'bon');
    await tester.tap(find.byKey(const ValueKey('email-submit')));
    await tester.pumpAndSettle();
    expect(typed, ['mauvais', 'bon']);
    expect(find.byKey(const ValueKey('email-error')), findsNothing);
  });

  testWidgets('offline: a clear message, the code is suggested', (tester) async {
    await pump(
      tester,
      onSend: () async => const AuthResult.failed(AuthError.offline),
      onSubmit: (_) async => null,
    );
    await tester.tap(find.byKey(const ValueKey('email-send')));
    await tester.pumpAndSettle();
    expect(
      find.text('Pas de connexion Internet. Réessayez plus tard, ou utilisez votre code de récupération.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('email-password')), findsNothing);
  });
}
