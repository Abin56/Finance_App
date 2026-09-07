import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Builds a [TextTheme] using Google Fonts' "Plus Jakarta Sans" for a premium,
/// modern look while keeping Material 3's default type scale proportions.
///
/// Theme V2 hierarchy (financial amounts are the focal point, so the top of
/// the scale carries real weight and tabular figures):
/// - `displayLarge`/`displayMedium` — the display financial amount / large
///   balance (e.g. the hero card's "₹86,290"), 700, tabular figures.
/// - `headlineLarge`/`headlineMedium`/`headlineSmall` — section titles and
///   secondary numeric/statistic values, 600–700, tabular figures.
/// - `titleLarge`/`titleMedium`/`titleSmall` — screen/app-bar titles and
///   card titles, 600.
/// - `bodyLarge`/`bodyMedium` — body text, default weight.
/// - `bodySmall` — supporting/secondary text.
/// - `labelLarge` — button labels, 600.
/// - `labelMedium` — navigation labels, 600.
/// - `labelSmall` — captions, 500.
TextTheme buildTextTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;

  const tabularFigures = [FontFeature.tabularFigures()];

  return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
    // Display financial amount / large balance — the focal number on a
    // screen (hero card total, account/card detail balance).
    displayLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.displayLarge,
      fontWeight: FontWeight.w700,
      fontFeatures: tabularFigures,
      letterSpacing: -0.5,
    ),
    displayMedium: GoogleFonts.plusJakartaSans(
      textStyle: base.displayMedium,
      fontWeight: FontWeight.w700,
      fontFeatures: tabularFigures,
      letterSpacing: -0.5,
    ),
    displaySmall: GoogleFonts.plusJakartaSans(
      textStyle: base.displaySmall,
      fontWeight: FontWeight.w700,
      fontFeatures: tabularFigures,
    ),
    // Section titles / secondary numeric-statistic values.
    headlineLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.headlineLarge,
      fontWeight: FontWeight.w700,
      fontFeatures: tabularFigures,
    ),
    headlineMedium: GoogleFonts.plusJakartaSans(
      textStyle: base.headlineMedium,
      fontWeight: FontWeight.w700,
      fontFeatures: tabularFigures,
    ),
    headlineSmall: GoogleFonts.plusJakartaSans(
      textStyle: base.headlineSmall,
      fontWeight: FontWeight.w600,
      fontFeatures: tabularFigures,
    ),
    // Screen/app-bar titles and card titles.
    titleLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.titleLarge,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      textStyle: base.titleMedium,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: GoogleFonts.plusJakartaSans(
      textStyle: base.titleSmall,
      fontWeight: FontWeight.w600,
    ),
    // Body / supporting text.
    bodyLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.bodyLarge,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: GoogleFonts.plusJakartaSans(
      textStyle: base.bodyMedium,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: GoogleFonts.plusJakartaSans(
      textStyle: base.bodySmall,
      fontWeight: FontWeight.w400,
    ),
    // Button / navigation labels / captions.
    labelLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.labelLarge,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: GoogleFonts.plusJakartaSans(
      textStyle: base.labelMedium,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: GoogleFonts.plusJakartaSans(
      textStyle: base.labelSmall,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Named financial-typography roles on top of the ambient [TextTheme], for
/// widgets that need a style by *purpose* (an amount, a statistic) rather
/// than by Material's generic display/headline/title slots. Thin wrappers —
/// no new fonts, no new weights beyond what [buildTextTheme] already set,
/// just a clearer name at call sites like [FlowFiAmountText].
abstract class AppTextStyles {
  AppTextStyles._();

  /// The largest financial number on a screen — a hero card's total balance.
  static TextStyle? displayAmount(BuildContext context) =>
      Theme.of(context).textTheme.displayLarge;

  /// A secondary/smaller balance figure — a summary card's own total.
  static TextStyle? largeBalance(BuildContext context) =>
      Theme.of(context).textTheme.headlineLarge;

  /// A compact numeric/statistic value (a stat tile, a quick-glance figure).
  static TextStyle? statisticValue(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge;
}
