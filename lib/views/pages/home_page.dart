import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/providers/language_provider.dart';
import '../../cores/themes/app_colors.dart';
import '../components/home_tile.dart';
import '../components/language_switcher.dart';
import '../routes.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const double _gap = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);

    String title({required String mg, required String fr}) =>
        switch (language) {
          AppLanguage.mg => mg,
          AppLanguage.fr => fr,
        };

    // La navigation des autres sections sera branchée quand leurs pages existeront.
    void openSection() {}

    final tiles = [
      HomeTile(
        icon: Symbols.menstrual_health,
        title: title(mg: 'Ny fadimbolanako', fr: 'Mes règles'),
        onTap: () => Navigator.pushNamed(context, AppRoutes.cycle),
        iconColor: AppColors.red,
        iconBackground: AppColors.red,
      ),
      HomeTile(
        icon: Symbols.pregnancy,
        title: title(mg: 'Ny vohokako', fr: 'Ma grossesse'),
        onTap: openSection,
      ),
      HomeTile(
        icon: Symbols.breastfeeding,
        title: title(mg: 'Ny zanako', fr: 'Mon enfant'),
        onTap: openSection,
      ),
      HomeTile(
        icon: Symbols.blood_pressure,
        title: title(
          mg: 'Tsy fahampian-tsakafo sy fandraisana an-tanana',
          fr: 'Malnutrition et prise en charge',
        ),
        onTap: openSection,
        iconColor: AppColors.red,
        iconBackground: AppColors.red,
      ),
    ];

    Widget row(Widget left, Widget right) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: _gap),
        Expanded(child: right),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('TARANAKA'),
        actions: const [LanguageSwitcher()],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Grille 2 x 2, sauf si le texte agrandi par l'utilisateur couperait
            // les mots en deux : les tuiles s'empilent alors sur une colonne.
            final tileWidth = (constraints.maxWidth - _gap * 3) / 2;
            final fitsTwoColumns =
                tileWidth >=
                HomeTile.minWidthFor(MediaQuery.textScalerOf(context));
            final lines = fitsTwoColumns
                ? [row(tiles[0], tiles[1]), row(tiles[2], tiles[3])]
                : tiles;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(_gap),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - _gap * 2,
                ),
                // Remplit l'écran et, si le contenu dépasse, donne aux tuiles
                // la hauteur de la plus haute puis laisse défiler.
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: _gap,
                    children: [for (final line in lines) Expanded(child: line)],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
