import 'package:flutter/material.dart';

import 'colors.dart';
import 'shapes.dart';
import 'spacing.dart';
import 'typography.dart';

/// Aggregated [ThemeData] for Homa Finance, light + dark.
///
/// All visual decisions come from `docs/DESIGN.md` via the theme tokens
/// in `colors.dart`, `typography.dart`, `shapes.dart`, `spacing.dart`.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppColors.lightScheme);
  static ThemeData dark() => _build(AppColors.darkScheme);

  static ThemeData _build(ColorScheme scheme) {
    final textTheme = AppTypography.textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,

      // Cards: white on warm surfaces, no border, soft ambient shadow.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.primary.withValues(alpha: 0.04),
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppBorderRadius.lg),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),

      // Primary filled buttons — clay fill, white text, base radius.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: AppBorderRadius.base,
          ),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),

      // Secondary "ghost" buttons — outlined with low-opacity neutral.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          side: BorderSide(
            color: scheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: AppBorderRadius.base,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: AppBorderRadius.base,
          ),
        ),
      ),

      // Inputs: tertiary-tinted fill, no border, primary border on focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppBorderRadius.base,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppBorderRadius.base,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppBorderRadius.base,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppBorderRadius.base,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      // Pill chips with low-saturation backgrounds.
      chipTheme: ChipThemeData(
        backgroundColor: scheme.secondaryContainer,
        labelStyle: textTheme.labelMedium,
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(
          borderRadius: AppBorderRadius.full,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.1),
        thickness: 1,
        space: 1,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: AppBorderRadius.md,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
