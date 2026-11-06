import 'package:flutter/material.dart';

import '../../cores/themes/app_colors.dart';

/// Grande tuile de l'accueil : une icône au-dessus de son titre.
class HomeTile extends StatelessWidget {
  /// Largeur à réserver au texte pour que le plus long mot des titres
  /// (« fadimbolanako ») tienne sur une ligne.
  static double minWidthFor(TextScaler scaler) =>
      _horizontalPadding * 2 + scaler.scale(_fontSize) * 7;

  static const double _horizontalPadding = 8;
  static const double _fontSize = 17;

  const HomeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor = AppColors.primaryDark,
    this.iconBackground = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color iconColor;

  /// Teinte du disque derrière l'icône, éclaircie à l'affichage.
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _horizontalPadding,
            vertical: 12,
          ),
          // Icône et titre de part et d'autre du milieu : les icônes d'une même
          // rangée restent alignées quelle que soit la longueur des titres.
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: iconBackground.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Icon(icon, size: 56, color: iconColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: _fontSize,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
