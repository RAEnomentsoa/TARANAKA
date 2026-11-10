import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/alerts/alert_contact.dart';
import 'package:taranaka/core/alerts/red_alert_screen.dart';
import 'package:taranaka/core/i18n/fallback_localizations.dart';
import 'package:taranaka/core/i18n/l10n.dart';
import 'package:taranaka/core/platform/phone_caller.dart';

import '../../helpers/config_fixture.dart';

/// The red alert alone (no database): the saved centre, one-tap call.
void main() {
  const bleeding = <String, Object?>{'code': 'saignement_vaginal', 'fr': 'Saignement vaginal'};
  const csb = AlertContact(
    centreName: 'CSB2 Ambohitsoa',
    centrePhone: '034 00 000 00',
    centreDirections: "Route d'Antsirabe, après le marché",
  );

  Future<void> pump(
    WidgetTester tester,
    AlertContact contact, {
    String kind = 'grossesse',
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...frameworkDelegates],
        home: RedAlertScreen(config: sampleConfig(), signs: const [bleeding], contact: contact, kind: kind),
      ),
    );
    await tester.pump();
  }

  testWidgets('title, message, saved centre with phone and directions, close', (tester) async {
    await pump(tester, csb);
    expect(find.text('URGENCE : consultez immédiatement !'), findsOneWidget);
    expect(find.text('Vous avez signalé un saignement vaginal.'), findsOneWidget);
    expect(find.text('Rendez-vous immédiatement dans une maternité ou un centre de santé.'), findsOneWidget);
    expect(find.text('CSB2 Ambohitsoa'), findsOneWidget);
    expect(find.text('034 00 000 00'), findsOneWidget);
    expect(find.text("Route d'Antsirabe, après le marché"), findsOneWidget);
    expect(find.text('Appeler mon centre de santé'), findsOneWidget);
    expect(find.text('Ouvrir l\'itinéraire'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('alert-close')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cette alerte ne remplace pas un diagnostic.'), findsOneWidget);
    expect(find.text('Fermer l\'alerte'), findsOneWidget);
    expect(find.textContaining('Paramètres'), findsNothing);
  });

  testWidgets('"Appeler mon centre de santé" calls the saved number at once', (tester) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('taranaka/phone'), (
      call,
    ) async {
      calls.add(call.arguments);
      return 'called';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('taranaka/phone'),
        null,
      ),
    );
    await pump(tester, csb);
    await tester.tap(find.byKey(const ValueKey('alert-call')));
    await tester.pump();
    expect(calls, [
      {'number': '0340000000'},
    ]);
  });

  testWidgets('the call button is visible without scrolling on a small phone', (tester) async {
    await pump(tester, csb, size: const Size(320, 568));
    final button = tester.getRect(find.byKey(const ValueKey('alert-call')));
    expect(button.bottom, lessThanOrEqualTo(568));
    expect(button.height, greaterThanOrEqualTo(48));
  });

  testWidgets('emergency instructions: folded, one tap away', (tester) async {
    await pump(tester, csb);
    expect(find.textContaining('ne mettez rien dans le vagin'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('alert-instructions')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text("Consignes d'urgence"));
    await tester.pumpAndSettle();
    expect(find.textContaining('ne mettez rien dans le vagin'), findsOneWidget);
  });

  testWidgets('no centre saved: a button to add it, no call button', (tester) async {
    await pump(tester, const AlertContact());
    expect(find.byKey(const ValueKey('alert-call')), findsNothing);
    expect(find.text('Ajouter mon centre de santé'), findsOneWidget);
  });

  testWidgets('only the agent number: it becomes the main call button', (tester) async {
    await pump(tester, const AlertContact(agentPhone: '032 11 111 11'), kind: 'enfant');
    expect(find.text("Emmenez immédiatement l'enfant dans un centre de santé."), findsOneWidget);
    expect(find.text("Appeler l'agent communautaire (032 11 111 11)"), findsOneWidget);
  });

  test('numbers keep only what a dialer understands', () {
    expect(PhoneCaller.clean('034 00-000.00'), '0340000000');
    expect(PhoneCaller.clean('+261 34 00 000 00'), '+261340000000');
  });
}
