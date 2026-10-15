import 'package:flutter/widgets.dart';

/// Radius scale from `docs/DESIGN.md` `rounded` block.
///
/// Use these tokens instead of raw `BorderRadius.circular(n)` literals.
class AppRadius {
  AppRadius._();

  static const double sm = 4; // 0.25rem
  static const double base = 8; // DEFAULT (0.5rem) — buttons, inputs
  static const double md = 12; // 0.75rem
  static const double lg = 16; // 1rem — cards
  static const double xl = 24; // 1.5rem — large containers
  static const double full = 9999; // pills / chips
}

class AppBorderRadius {
  AppBorderRadius._();

  static const BorderRadius sm =
      BorderRadius.all(Radius.circular(AppRadius.sm));
  static const BorderRadius base =
      BorderRadius.all(Radius.circular(AppRadius.base));
  static const BorderRadius md =
      BorderRadius.all(Radius.circular(AppRadius.md));
  static const BorderRadius lg =
      BorderRadius.all(Radius.circular(AppRadius.lg));
  static const BorderRadius xl =
      BorderRadius.all(Radius.circular(AppRadius.xl));
  static const BorderRadius full =
      BorderRadius.all(Radius.circular(AppRadius.full));
}
