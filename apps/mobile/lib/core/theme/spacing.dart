/// Spacing scale from `docs/DESIGN.md` (8px base unit).
///
/// Use these constants for all padding/margin values. Avoid literals
/// like `EdgeInsets.all(13)` — if a value isn't here, add it here first.
class AppSpacing {
  AppSpacing._();

  static const double unit = 8;

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24; // gutter
  static const double xl = 32;
  static const double xxl = 40; // margin-desktop
  static const double xxxl = 64;

  static const double marginMobile = 16;
  static const double marginDesktop = 40;
  static const double containerMax = 1280;
}
