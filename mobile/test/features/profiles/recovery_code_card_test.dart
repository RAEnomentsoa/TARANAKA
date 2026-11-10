import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/i18n/fallback_localizations.dart';
import 'package:taranaka/core/i18n/l10n.dart';
import 'package:taranaka/core/security/pin_crypto.dart';
import 'package:taranaka/features/profiles/presentation/recovery_code_card.dart';

void main() {
  testWidgets('6 codes in one block, one copy icon for all, one Télécharger button', (tester) async {
    final codes = PinCrypto().newRecoveryCodes();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    var saved = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...frameworkDelegates],
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecoveryCodeCard(code: PinCrypto.joinRecoveryCodes(codes), onSaved: () => saved++),
          ),
        ),
      ),
    );
    final block = find.byKey(const ValueKey('recovery-codes-block'));
    for (final (i, c) in codes.indexed) {
      expect(find.descendant(of: block, matching: find.byKey(ValueKey('recovery-code-$i'))), findsOneWidget);
      expect(find.text(c), findsOneWidget);
    }
    // One copy button (inside the block), one download button, nothing per code.
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.descendant(of: block, matching: find.byIcon(Icons.copy_outlined)), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-code-download')), findsOneWidget);
    expect(find.text('Télécharger'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recovery-code-copy')));
    await tester.pump();
    expect(copied, codes.join('\n'));
    expect(saved, 1);
  });
}
