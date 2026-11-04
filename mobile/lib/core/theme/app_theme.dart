import 'package:flutter/material.dart';

import 'tokens.dart';

/// The single Material 3 theme of the app (light only: a dark theme is not
/// shipped until it has been tested for readability, as the skill asks).
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentSoft,
    onPrimaryContainer: AppColors.accentPressed,
    secondaryContainer: AppColors.accentSoft,
    onSecondaryContainer: AppColors.accentPressed,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.background,
    surfaceContainer: AppColors.background,
    outline: AppColors.outline,
    outlineVariant: AppColors.accentSoftBorder,
    error: AppColors.danger,
    errorContainer: AppColors.dangerSoft,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  final text = base.textTheme.copyWith(
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.4),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m));
  const minButton = Size(Space.touch, Space.touch);

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        side: const BorderSide(color: AppColors.accentSoftBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(Space.touchLarge - 8),
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(Space.touch),
        shape: shape,
        side: const BorderSide(color: AppColors.accent),
        foregroundColor: AppColors.accent,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: minButton, textStyle: text.labelLarge),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: minButton),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.m)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.m),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.l),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accentSoft,
      side: const BorderSide(color: AppColors.outline),
      labelStyle: text.bodyMedium,
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: Space.m,
      contentPadding: EdgeInsets.symmetric(horizontal: Space.l),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.accentSoftBorder, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        // Light fade/zoom instead of heavier transitions (performance, skill).
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
