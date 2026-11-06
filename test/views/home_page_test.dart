import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/cores/data/database_helper.dart';
import 'package:taranaka/cores/data/table_repository.dart';
import 'package:taranaka/cores/models/cycle.dart';
import 'package:taranaka/cores/providers/language_provider.dart';
import 'package:taranaka/cores/providers/table_providers.dart';
import 'package:taranaka/cores/themes/app_colors.dart';
import 'package:taranaka/cores/themes/app_theme.dart';
import 'package:taranaka/views/components/home_tile.dart';
import 'package:taranaka/views/components/language_flag_button.dart';
import 'package:taranaka/views/pages/cycle_page.dart';
import 'package:taranaka/views/pages/home_page.dart';
import 'package:taranaka/views/routes.dart';

class _EmptyCycleRepository extends TableRepository<Cycle> {
  _EmptyCycleRepository() : super(DatabaseHelper(), Cycle.table, Cycle.fromMap);

  @override
  Future<List<Cycle>> getAll({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async => const [];
}

const _malagasy = [
  'Ny fadimbolanako',
  'Ny vohokako',
  'Ny zanako',
  'Tsy fahampian-tsakafo sy fandraisana an-tanana',
];
const _french = [
  'Mes règles',
  'Ma grossesse',
  'Mon enfant',
  'Malnutrition et prise en charge',
];

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: const HomePage(),
        ),
      ),
    ),
  );
}

Finder _flag(AppLanguage language) => find.byWidgetPredicate(
  (w) => w is LanguageFlagButton && w.language == language,
);

void main() {
  testWidgets('affiche le malagasy par défaut et bascule avec les drapeaux', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('TARANAKA'), findsOneWidget);
    for (final title in _malagasy) {
      expect(find.text(title), findsOneWidget);
    }

    await tester.tap(_flag(AppLanguage.fr));
    await tester.pump();
    for (final title in _french) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text(_malagasy.first), findsNothing);

    await tester.tap(_flag(AppLanguage.mg));
    await tester.pump();
    for (final title in _malagasy) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('seules les tuiles Règles et Malnutrition ont l\'icône rouge', (
    tester,
  ) async {
    await _pump(tester);
    final colors = tester
        .widgetList<HomeTile>(find.byType(HomeTile))
        .map(
          (tile) => tester
              .widget<Icon>(
                find.descendant(
                  of: find.byWidget(tile),
                  matching: find.byIcon(tile.icon),
                ),
              )
              .color,
        );
    const red = Color(0xFFD32F2F);
    expect(colors.toList(), [
      red,
      AppColors.primaryDark,
      AppColors.primaryDark,
      red,
    ]);
  });

  testWidgets('la tuile « Mes règles » ouvre la section du cycle', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cycleRepositoryProvider.overrideWithValue(_EmptyCycleRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          initialRoute: AppRoutes.home,
          routes: AppRoutes.routes,
        ),
      ),
    );
    await tester.tap(find.text('Ny fadimbolanako'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CyclePage), findsOneWidget);
  });

  testWidgets('les drapeaux annoncent leur état aux lecteurs d\'écran', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(
      tester.getSemantics(_flag(AppLanguage.mg)),
      matchesSemantics(
        label: 'Malagasy',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        hasEnabledState: false,
      ),
    );
    handle.dispose();
  });

  testWidgets('zones tactiles conformes aux recommandations', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    expect(tester.getSize(_flag(AppLanguage.mg)), const Size(48, 48));
    handle.dispose();
  });

  for (final (name, size, scale, columns) in const [
    ('petit écran', Size(320, 568), 1.0, 2),
    ('téléphone standard', Size(390, 844), 1.0, 2),
    ('paysage', Size(844, 390), 1.0, 2),
    ('texte agrandi x1,5', Size(390, 844), 1.5, 1),
    ('petit écran, texte x2', Size(320, 568), 2.0, 1),
  ]) {
    testWidgets('quatre tuiles égales sans débordement : $name', (
      tester,
    ) async {
      await _pump(tester, size: size, textScale: scale);
      expect(tester.takeException(), isNull);

      final tiles = find.byType(HomeTile);
      expect(tiles, findsNWidgets(4));
      final sizes = {for (var i = 0; i < 4; i++) tester.getSize(tiles.at(i))};
      expect(sizes, hasLength(1), reason: 'tailles : $sizes');

      final firstColumn = tester.getTopLeft(tiles.at(0)).dx;
      final secondTile = tester.getTopLeft(tiles.at(1));
      expect(secondTile.dx > firstColumn, columns == 2);
      expect(secondTile.dy == tester.getTopLeft(tiles.at(0)).dy, columns == 2);
    });
  }
}
