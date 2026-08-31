import 'package:flutter/material.dart';

/// Centralized color palette for the app, used to build both
/// the light and dark [ColorScheme]s in `app_theme.dart`.
abstract class AppColors {
  AppColors._();

  // Brand — matches the companion web app's "Ocean blue" identity 1:1 (its
  // light/dark `--primary` CSS tokens convert to exactly these hex values).
  // Was an indigo/purple (#5B5FEF) before, which read as a different brand
  // from the web app entirely rather than the same product on two platforms.
  static const Color primary = Color(0xFF165DFC);
  static const Color primaryDark = Color(0xFF629FFF);
  static const Color secondary = Color(0xFF00C2A8);

  /// Matches the web app's `--purple` token — its fifth semantic accent
  /// (alongside primary/success/expense/warning), used for tags/badges that
  /// need a color outside the money-direction palette.
  static const Color purple = Color(0xFF8E51FF);

  // Semantic — matches the web app's `--success`/`--expense`/`--warning`
  // tokens (converted from their oklch values: #00BC7D / #FB2C36 / #FE9A00).
  static const Color income = Color(0xFF00BC7D);
  static const Color expense = Color(0xFFFB2C36);
  static const Color pending = Color(0xFFFE9A00);
  static const Color savings = Color(0xFF3E8EFF);
  static const Color credit = Color(0xFF00BC7D);
  static const Color debit = Color(0xFFFB2C36);

  // Light surfaces
  static const Color lightBackground = Color(0xFFF7F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEFEFF6);
  static const Color lightOutline = Color(0xFFE2E2EE);

  // Dark surfaces
  static const Color darkBackground = Color(0xFF0F1014);
  static const Color darkSurface = Color(0xFF1A1B22);
  static const Color darkSurfaceVariant = Color(0xFF24252E);
  static const Color darkOutline = Color(0xFF33343F);

  // Text
  static const Color lightTextPrimary = Color(0xFF14141C);
  static const Color lightTextSecondary = Color(0xFF6B6C7A);
  static const Color darkTextPrimary = Color(0xFFF2F2F7);
  static const Color darkTextSecondary = Color(0xFFA0A1AE);

  // Status
  static const Color success = Color(0xFF00BC7D);
  static const Color warning = Color(0xFFFE9A00);
  static const Color error = Color(0xFFFB2C36);
  static const Color info = Color(0xFF3E8EFF);

  // Category palette (used as default colors when creating custom categories)
  // — first swatch matches [primary] so the default pick stays on-brand.
  static const List<Color> categoryPalette = [
    Color(0xFF165DFC),
    Color(0xFF00C2A8),
    Color(0xFFFB2C36),
    Color(0xFFFE9A00),
    Color(0xFF3E8EFF),
    Color(0xFF00BC7D),
    Color(0xFFE85D9A),
    Color(0xFF8E51FF),
    Color(0xFF40C4FF),
    Color(0xFFFFC857),
  ];

  // Gradients — blue family throughout, matching the web app's "Ocean blue"
  // gradient language (navy -> royal -> azure) instead of the old purple.
  static const List<Color> primaryGradient = [Color(0xFF3B82F6), Color(0xFF1D4ED8)];
  static const List<Color> incomeGradient = [Color(0xFF00BC7D), Color(0xFF0E9F6E)];
  static const List<Color> savingsGradient = [Color(0xFF3E8EFF), Color(0xFF165DFC)];
}
