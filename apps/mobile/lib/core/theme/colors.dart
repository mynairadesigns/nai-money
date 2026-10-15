import 'package:flutter/material.dart';

/// Material 3 [ColorScheme]s for Homa Finance.
///
/// Brand: London bus red (#DA291C) on clean, near-neutral surfaces.
///
/// Semantics the UI relies on:
///   - `primary` (red)     → brand, primary buttons, expense amounts
///   - `secondary` (green) → income amounts / positive deltas
///   - `tertiary` (navy)   → neutral accents (charts, chips)
class AppColors {
  AppColors._();

  /// London bus red.
  static const brandRed = Color(0xFFDA291C);

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: brandRed,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDAD4),
    onPrimaryContainer: Color(0xFF410000),
    secondary: Color(0xFF1E7A46),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFC8EED3),
    onSecondaryContainer: Color(0xFF00210F),
    tertiary: Color(0xFF2B3A5C),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD9E2FF),
    onTertiaryContainer: Color(0xFF0B1A3A),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFCFCFC),
    onSurface: Color(0xFF1B1B1F),
    onSurfaceVariant: Color(0xFF4D4546),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F6F6),
    surfaceContainer: Color(0xFFF1F0F0),
    surfaceContainerHigh: Color(0xFFEBEAEA),
    surfaceContainerHighest: Color(0xFFE5E4E4),
    surfaceDim: Color(0xFFDCDBDB),
    surfaceBright: Color(0xFFFCFCFC),
    surfaceTint: brandRed,
    outline: Color(0xFF807475),
    outlineVariant: Color(0xFFD3C3C3),
    inverseSurface: Color(0xFF303034),
    onInverseSurface: Color(0xFFF3EFF0),
    inversePrimary: Color(0xFFFFB4A9),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static final ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: brandRed,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFFEF3B2D),
    onPrimary: const Color(0xFFFFFFFF),
    primaryContainer: const Color(0xFF7A0F08),
    onPrimaryContainer: const Color(0xFFFFDAD4),
    secondary: const Color(0xFF7FDA9C),
    onSecondary: const Color(0xFF003919),
    secondaryContainer: const Color(0xFF005228),
    onSecondaryContainer: const Color(0xFF9BF7B6),
    tertiary: const Color(0xFFB4C5F0),
    onTertiary: const Color(0xFF1C2B4C),
    tertiaryContainer: const Color(0xFF334366),
    onTertiaryContainer: const Color(0xFFD9E2FF),
    surface: const Color(0xFF141315),
    onSurface: const Color(0xFFE6E1E3),
    onSurfaceVariant: const Color(0xFFD3C3C3),
    surfaceContainerLowest: const Color(0xFF0F0E10),
    surfaceContainerLow: const Color(0xFF1C1B1D),
    surfaceContainer: const Color(0xFF201F21),
    surfaceContainerHigh: const Color(0xFF2B292C),
    surfaceContainerHighest: const Color(0xFF363437),
    inverseSurface: const Color(0xFFE6E1E3),
    onInverseSurface: const Color(0xFF313033),
    inversePrimary: brandRed,
    outline: const Color(0xFF9C8D8D),
    outlineVariant: const Color(0xFF4D4546),
  );
}
