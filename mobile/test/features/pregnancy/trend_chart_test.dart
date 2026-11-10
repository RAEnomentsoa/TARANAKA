import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/theme/tokens.dart';
import 'package:taranaka/features/pregnancy/domain/follow_up_checks.dart';
import 'package:taranaka/features/pregnancy/presentation/trend_chart.dart';

/// The evolution charts of "Mon suivi de grossesse": drawn at any width,
/// one point or many, with a spoken summary and a legend by shape.
void main() {
  Future<void> pump(WidgetTester tester, Widget chart, {double width = 320}) async {
    tester.view.physicalSize = Size(width, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListView(children: [chart])),
      ),
    );
  }

  testWidgets('blood pressure: two lines, dashed limits, legend and summary', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const TrendChart(
        series: [
          TrendSeries(
            label: 'Haute',
            color: AppColors.danger,
            points: [TrendPoint(12, 110), TrendPoint(20, 118), TrendPoint(30.5, 145)],
          ),
          TrendSeries(
            label: 'Basse',
            color: AppColors.accent,
            square: true,
            points: [TrendPoint(12, 70), TrendPoint(20, 74), TrendPoint(30.5, 95)],
          ),
        ],
        limits: [TrendLimit(140, AppColors.danger), TrendLimit(90, AppColors.warning)],
        semanticLabel: 'Dernière tension : 145/95 mmHg à 30 SA.',
        weeksLabel: 'SA',
        step: 10,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Haute'), findsOneWidget);
    expect(find.text('Basse'), findsOneWidget);
    expect(find.bySemanticsLabel('Dernière tension : 145/95 mmHg à 30 SA.'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a single weight point is drawn without error', (tester) async {
    await pump(
      tester,
      const TrendChart(
        series: [
          TrendSeries(label: 'Poids', color: AppColors.accent, points: [TrendPoint(16, 58.5)]),
        ],
        semanticLabel: 'Dernier poids : 58,5 kg à 16 SA.',
        weeksLabel: 'SA',
        step: 2,
      ),
      width: 280,
    );
    expect(tester.takeException(), isNull);
    // One line only: no legend needed.
    expect(find.text('Poids'), findsNothing);
  });
}
