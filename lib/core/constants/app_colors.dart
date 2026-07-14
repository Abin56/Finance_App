import 'package:flutter/material.dart';

/// Centralized color palette for the app, used to build both
/// the light and dark [ColorScheme]s in `app_theme.dart`.
abstract class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF5B5FEF);
  static const Color primaryDark = Color(0xFF8B8FFF);
  static const Color secondary = Color(0xFF00C2A8);

  // Semantic
  static const Color income = Color(0xFF1FB873);
  static const Color expense = Color(0xFFFF5B5B);
  static const Color pending = Color(0xFFFFA53E);
  static const Color savings = Color(0xFF3E8EFF);
  static const Color credit = Color(0xFF1FB873);
  static const Color debit = Color(0xFFFF5B5B);

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
  static const Color success = Color(0xFF1FB873);
  static const Color warning = Color(0xFFFFA53E);
  static const Color error = Color(0xFFFF5B5B);
  static const Color info = Color(0xFF3E8EFF);

  // Category palette (used as default colors when creating custom categories)
  static const List<Color> categoryPalette = [
    Color(0xFF5B5FEF),
    Color(0xFF00C2A8),
    Color(0xFFFF5B5B),
    Color(0xFFFFA53E),
    Color(0xFF3E8EFF),
    Color(0xFF1FB873),
    Color(0xFFE85D9A),
    Color(0xFF8E6CEF),
    Color(0xFF40C4FF),
    Color(0xFFFFC857),
  ];

  // Gradients
  static const List<Color> primaryGradient = [Color(0xFF5B5FEF), Color(0xFF8B5FEF)];
  static const List<Color> incomeGradient = [Color(0xFF1FB873), Color(0xFF0F9D6B)];
  static const List<Color> expenseGradient = [Color(0xFFFF5B5B), Color(0xFFFF8B5B)];
  static const List<Color> savingsGradient = [Color(0xFF3E8EFF), Color(0xFF5B5FEF)];
}
