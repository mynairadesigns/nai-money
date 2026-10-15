import 'package:flutter/material.dart';

/// Material 3 [ColorScheme]s for Moneymind.
///
/// Light scheme maps the `docs/DESIGN.md` `colors` block 1:1.
/// Dark scheme is derived from the primary clay seed since DESIGN.md
/// specifies only light-mode tokens; the few `inverse-*` hints from
/// DESIGN.md are applied as explicit overrides.
class AppColors {
  AppColors._();

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF8A4F37),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD48C70),
    onPrimaryContainer: Color(0xFF582712),
    secondary: Color(0xFF526256),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD5E7D8),
    onSecondaryContainer: Color(0xFF58685C),
    tertiary: Color(0xFF615E57),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFA29D95),
    onTertiaryContainer: Color(0xFF37352F),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    surface: Color(0xFFFFF8F5),
    onSurface: Color(0xFF1E1B18),
    onSurfaceVariant: Color(0xFF53433E),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFBF2ED),
    surfaceContainer: Color(0xFFF5ECE7),
    surfaceContainerHigh: Color(0xFFEFE6E2),
    surfaceContainerHighest: Color(0xFFE9E1DC),
    surfaceDim: Color(0xFFE1D8D4),
    surfaceBright: Color(0xFFFFF8F5),
    surfaceTint: Color(0xFF8A4F37),
    outline: Color(0xFF85736D),
    outlineVariant: Color(0xFFD8C2BB),
    inverseSurface: Color(0xFF34302C),
    onInverseSurface: Color(0xFFF8EFEA),
    inversePrimary: Color(0xFFFFB599),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static final ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8A4F37),
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFFFFB599),
    onPrimary: const Color(0xFF582712),
    primaryContainer: const Color(0xFF6E3822),
    onPrimaryContainer: const Color(0xFFFFDBCE),
    secondary: const Color(0xFFBACBBD),
    onSecondary: const Color(0xFF243429),
    secondaryContainer: const Color(0xFF3B4A3F),
    onSecondaryContainer: const Color(0xFFD5E7D8),
    surface: const Color(0xFF1A1614),
    onSurface: const Color(0xFFF8EFEA),
    onSurfaceVariant: const Color(0xFFD8C2BB),
    inverseSurface: const Color(0xFFF8EFEA),
    onInverseSurface: const Color(0xFF34302C),
    inversePrimary: const Color(0xFF8A4F37),
    outline: const Color(0xFFA08D85),
    outlineVariant: const Color(0xFF53433E),
  );
}
