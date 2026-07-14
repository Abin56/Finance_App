import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Builds a [TextTheme] using Google Fonts' "Plus Jakarta Sans" for a premium,
/// modern look while keeping Material 3's default type scale proportions.
TextTheme buildTextTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;

  return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
    displayLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.displayLarge,
      fontWeight: FontWeight.w700,
    ),
    headlineLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.headlineLarge,
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: GoogleFonts.plusJakartaSans(
      textStyle: base.headlineMedium,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: GoogleFonts.plusJakartaSans(
      textStyle: base.headlineSmall,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.titleLarge,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      textStyle: base.titleMedium,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: GoogleFonts.plusJakartaSans(textStyle: base.bodyLarge),
    bodyMedium: GoogleFonts.plusJakartaSans(textStyle: base.bodyMedium),
    labelLarge: GoogleFonts.plusJakartaSans(
      textStyle: base.labelLarge,
      fontWeight: FontWeight.w600,
    ),
  );
}
