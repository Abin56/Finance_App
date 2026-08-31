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

  // Radius — flat/sharp-cornered design language: every rounded surface in the app
  // resolves through these constants, so zeroing them here flattens cards, buttons,
  // inputs, chips, bottom sheets, and dialogs app-wide from one place, without
  // touching the widgets that reference them. [radiusPill] stays at 999 — that's a
  // genuine pill/circle shape (nav indicators, filter chips), not a "rounded
  // rectangle" corner, so it's deliberately left alone (mirrors the web app's
  // decision to keep `rounded-full` untouched while flattening its numbered scale).
  static const double radiusSm = 0;
  static const double radiusMd = 0;
  static const double radiusLg = 0;
  static const double radiusXl = 0;
  static const double radiusPill = 999;

  /// Premium dashboard card radius (Figma spec) — distinct from [radiusLg]/
  /// [radiusXl], used by the redesigned Dashboard's hero/summary cards.
  static const double radiusCard = 0;

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

  // Component heights
  static const double buttonHeight = 52;
  static const double bottomNavHeight = 64;

  /// Bottom padding a scrollable needs so its last item can scroll clear of
  /// the floating "+" button: the 64pt FAB plus its 16pt margin, and [lg]
  /// again so content rests below it rather than flush against it.
  static const double fabClearance = 96;
}
