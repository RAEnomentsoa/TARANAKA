import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/i18n/fallback_localizations.dart';
import 'package:taranaka/core/i18n/l10n.dart';
import 'package:taranaka/core/widgets/date_field.dart';

/// The date wheels that replace every calendar picker.
void main() {
  Future<List<DateTime>> pump(
    WidgetTester tester, {
    required DateTime first,
    required DateTime last,
    DateTime? value,
    String locale = 'fr',
    bool withTime = false,
  }) async {
    final picked = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...frameworkDelegates],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DateField(
              key: const ValueKey('field'),
              label: 'Date',
              value: value,
              first: first,
              last: last,
              withTime: withTime,
              onChanged: (d) => setState(() {
                picked.add(d);
                value = d;
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  Future<void> scrollWheel(WidgetTester tester, int wheel, int items) async {
    await tester.drag(find.byType(CupertinoPicker).at(wheel), Offset(0, -48.0 * items), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('no calendar grid: day, month and year wheels', (tester) async {
    await pump(
      tester,
      first: DateTime(2024, 1, 1),
      last: DateTime(2026, 11, 4),
      value: DateTime(2026, 6, 15),
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    expect(find.text('juin'), findsOneWidget);
    expect(find.text('15/06/2026'), findsWidgets);
  });

  testWidgets('scrolling a wheel changes the date; a past date can be chosen', (tester) async {
    final picked = await pump(
      tester,
      first: DateTime(2024, 1, 1),
      last: DateTime(2026, 11, 4),
      value: DateTime(2026, 6, 15),
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    await scrollWheel(tester, 1, -3); // month: June → March
    expect(find.byKey(const ValueKey('date-wheel-value')), findsOneWidget);
    expect(find.text('15/03/2026'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('date-wheel-ok')));
    await tester.pumpAndSettle();
    expect(picked, [DateTime(2026, 3, 15)]);
    expect(find.text('15/03/2026'), findsOneWidget);
  });

  testWidgets('a date out of the limits is brought back inside', (tester) async {
    await pump(
      tester,
      first: DateTime(2026, 1, 10),
      last: DateTime(2026, 11, 4),
      value: DateTime(2026, 10, 31),
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    await scrollWheel(tester, 1, 1); // October → November 31st → 4 November (last day allowed)
    expect(find.text('04/11/2026'), findsWidgets);
  });

  testWidgets('31 March → February keeps a real day', (tester) async {
    await pump(
      tester,
      first: DateTime(2020, 1, 1),
      last: DateTime(2026, 12, 31),
      value: DateTime(2026, 3, 31),
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    await scrollWheel(tester, 1, -1);
    expect(find.text('28/02/2026'), findsWidgets);
  });

  testWidgets('date and time wheels, month names in English', (tester) async {
    final picked = await pump(
      tester,
      first: DateTime(2026, 10, 1),
      last: DateTime(2026, 11, 4, 9, 30),
      value: DateTime(2026, 11, 3, 8, 15),
      locale: 'en',
      withTime: true,
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPicker), findsNWidgets(5));
    expect(find.text('November'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    await scrollWheel(tester, 3, 2); // 08 h → 10 h
    await tester.tap(find.byKey(const ValueKey('date-wheel-ok')));
    await tester.pumpAndSettle();
    expect(picked, [DateTime(2026, 11, 3, 10, 15)]);
  });

  testWidgets('Malagasy: month names and framework texts are in Malagasy', (tester) async {
    await pump(
      tester,
      first: DateTime(2026, 1, 1),
      last: DateTime(2026, 11, 4),
      value: DateTime(2026, 7, 1),
      locale: 'mg',
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pumpAndSettle();
    expect(find.text('Jolay'), findsOneWidget);
    expect(find.text('Hamafiso'), findsOneWidget);
    final context = tester.element(find.byType(DateWheelSheet));
    expect(MaterialLocalizations.of(context).backButtonTooltip, 'Miverina');
    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Hanafoana');
  });
}
