import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF00AEEF);

  /// Variante de [primary] pour les icônes et le texte sur fond blanc, où
  /// [primary] n'offre qu'un contraste de 2,5:1 (celle-ci : 6,7:1).
  static const Color primaryDark = Color(0xFF00628A);
  static const Color white = Color(0xFFFFFFFF);

  /// Rouge des icônes de tuile et des jours de règles (blanc dessus : 5:1).
  static const Color red = Color(0xFFD32F2F);

  /// Texte et contours posés sur les couleurs claires des phases.
  static const Color ink = Color(0xFF1F2933);

  // Phases du cycle.
  static const Color menstruation = red;
  static const Color follicular = Color(0xFF90CAF9);
  static const Color ovulation = Color(0xFF6A1B9A);
  static const Color luteal = Color(0xFFFFCC80);

  /// Signale un danger pour la santé.
  static const Color warning = Color(0xFFB71C1C);
}
