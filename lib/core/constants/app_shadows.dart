import 'package:flutter/material.dart';

import '../extensions/context_extensions.dart';

/// Soft, theme-aware card shadows for the premium Dashboard redesign. Kept
/// separate from `app_theme.dart`'s `cardTheme` (elevation 0 everywhere)
/// so this stays an opt-in look for specific premium cards rather than a
/// global elevation change across the app.
abstract class AppShadows {
  AppShadows._();

  static List<BoxShadow> soft(BuildContext context) {
    final isDark = context.isDarkMode;
    return [
      BoxShadow(
        color: (isDark ? Colors.black : context.colors.onSurface).withValues(alpha: isDark ? 0.28 : 0.06),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
