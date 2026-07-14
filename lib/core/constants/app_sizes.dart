/// Spacing, radius, and breakpoint constants kept in one place
/// so layout rhythm stays consistent across every screen.
abstract class AppSizes {
  AppSizes._();

  // Spacing scale (4pt grid)
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // Radius
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  /// Premium dashboard card radius (Figma spec) — distinct from [radiusLg]/
  /// [radiusXl], used by the redesigned Dashboard's hero/summary cards.
  static const double radiusCard = 24;

  // Icon sizes
  static const double iconSm = 16;
  static const double iconMd = 22;
  static const double iconLg = 28;
  static const double iconXl = 40;

  // Elevation / blur
  static const double blurSm = 12;
  static const double blurMd = 24;

  // Responsive breakpoints
  static const double breakpointMobile = 600;
  static const double breakpointTablet = 1024;
  static const double breakpointDesktop = 1440;

  // Component heights
  static const double buttonHeight = 52;
  static const double inputHeight = 56;
  static const double bottomNavHeight = 64;
  static const double appBarHeight = 64;
}
