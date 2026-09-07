import 'package:flutter/material.dart';

import '../extensions/context_extensions.dart';

/// The app's one restrained-elevation shadow system (Theme V2). Cards mostly
/// separate via background + a thin border (see `app_theme.dart`'s
/// `cardTheme`) rather than shadow — these two tiers exist for the rare
/// surface that still wants to read as "floating" (a hero card, a raised
/// sheet header), and are deliberately subtle: no multi-layer glow, no
/// claymorphism. Superset of the retired claymorphism system's equivalent
/// shadow helpers, which this replaced.
abstract class AppShadows {
  AppShadows._();

  static List<BoxShadow> soft(BuildContext context) {
    final isDark = context.isDarkMode;
    return [
      BoxShadow(
        color: (isDark ? Colors.black : context.colors.onSurface).withValues(
          alpha: isDark ? 0.28 : 0.06,
        ),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Stronger blur/offset than [soft] for the dashboard's single most
  /// prominent hero card, so it reads as sitting above every other card
  /// rather than at the same elevation.
  static List<BoxShadow> elevated(BuildContext context) {
    final isDark = context.isDarkMode;
    return [
      BoxShadow(
        color: (isDark ? Colors.black : context.colors.onSurface).withValues(
          alpha: isDark ? 0.36 : 0.10,
        ),
        blurRadius: 32,
        offset: const Offset(0, 12),
      ),
    ];
  }
}
