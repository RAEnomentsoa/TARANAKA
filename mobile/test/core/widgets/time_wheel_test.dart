import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/i18n/fallback_localizations.dart';
import 'package:taranaka/core/i18n/l10n.dart';
import 'package:taranaka/core/widgets/time_wheel.dart';

void main() {
  testWidgets('hour on the left, minute on the right, side by side', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...frameworkDelegates],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showTimeWheel(
                context,
                title: 'Heure',
                initial: const TimeOfDay(hour: 8, minute: 30),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('08:30'), findsOneWidget);
    final wheels = find.byType(CupertinoPicker);
    expect(wheels, findsNWidgets(2));
    final hour = tester.getCenter(wheels.at(0));
    final minute = tester.getCenter(wheels.at(1));
    expect(hour.dx, lessThan(minute.dx));
    expect((hour.dy - minute.dy).abs(), lessThan(1));

    await tester.drag(wheels.at(0), const Offset(0, -60));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('time-wheel-ok')));
    await tester.pumpAndSettle();
    expect(picked!.minute, 30);
    expect(picked!.hour, greaterThan(8));
  });
}
