import 'package:flutter/material.dart';

/// Design tokens (skill flutter-design: no hard-coded colours or sizes in widgets).
///
/// One accent colour (blue) on white and light-blue surfaces. Status colours
/// are semantic only and are always shown with an icon and a label, never alone.
abstract final class AppColors {
  /// Accent. White text on it: 5.9:1 (AA).
  static const Color accent = Color(0xFF0369A1);
  static const Color accentPressed = Color(0xFF075985);

  /// Light-blue surfaces (tiles, selected chips, headers).
  static const Color accentSoft = Color(0xFFE0F2FE);
  static const Color accentSoftBorder = Color(0xFFBAE6FD);

  static const Color background = Color(0xFFF5FAFE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFCBD5E1);

  /// Text. On white: 15.9:1 and 7.4:1.
  static const Color text = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF475569);

  // Semantic: urgency, sync and growth status. Dark tones so text on the soft
  // background stays AA.
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFEE4E2);
  static const Color warning = Color(0xFFB54708);
  static const Color warningSoft = Color(0xFFFEF0C7);
  static const Color caution = Color(0xFF854D0E);
  static const Color cautionSoft = Color(0xFFFEF9C3);
  static const Color success = Color(0xFF067647);
  static const Color successSoft = Color(0xFFDCFAE6);
  static const Color neutral = Color(0xFF475569);
  static const Color neutralSoft = Color(0xFFF1F5F9);
}

abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Minimum touch target (spec §12: 48 dp).
  static const double touch = 48;

  /// Large primary actions (PIN pad keys, tiles).
  static const double touchLarge = 64;

  /// Content is centred and capped on wide screens.
  static const double maxContentWidth = 560;
}

abstract final class Radii {
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
}
