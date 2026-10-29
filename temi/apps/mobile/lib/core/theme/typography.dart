import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale from `docs/DESIGN.md`.
///
/// Sora is the only allowed `fontFamily` — sourced via `google_fonts`.
/// Sizes/weights/letter-spacing/line-heights match DESIGN.md exactly.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(ColorScheme scheme) {
    final base = GoogleFonts.soraTextTheme();
    final onSurface = scheme.onSurface;

    return base.copyWith(
      // headline-xl (48 / 600 / 1.1 / -0.02em)
      displayLarge: GoogleFonts.sora(
        fontSize: 48,
        fontWeight: FontWeight.w600,
        height: 1.1,
        letterSpacing: -0.96, // -0.02em * 48
        color: onSurface,
      ),
      // headline-xl-mobile (36 / 600 / 1.2 / -0.02em)
      displayMedium: GoogleFonts.sora(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.72,
        color: onSurface,
      ),
      // headline-lg (32 / 600 / 1.2 / -0.01em)
      displaySmall: GoogleFonts.sora(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.32,
        color: onSurface,
      ),
      headlineLarge: GoogleFonts.sora(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: onSurface,
      ),
      // headline-md (24 / 500 / 1.3)
      headlineMedium: GoogleFonts.sora(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: onSurface,
      ),
      headlineSmall: GoogleFonts.sora(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: onSurface,
      ),
      titleLarge: GoogleFonts.sora(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: onSurface,
      ),
      titleMedium: GoogleFonts.sora(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: onSurface,
      ),
      titleSmall: GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: onSurface,
      ),
      // body-lg (18 / 400 / 1.6)
      bodyLarge: GoogleFonts.sora(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: onSurface,
      ),
      // body-md (16 / 400 / 1.6)
      bodyMedium: GoogleFonts.sora(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: onSurface,
      ),
      bodySmall: GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: scheme.onSurfaceVariant,
      ),
      // label-md (14 / 600 / 1.4 / 0.05em)
      labelLarge: GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.7, // 0.05em * 14
        color: onSurface,
      ),
      // label-sm (12 / 500 / 1.4)
      labelMedium: GoogleFonts.sora(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: onSurface,
      ),
      labelSmall: GoogleFonts.sora(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0.55,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
