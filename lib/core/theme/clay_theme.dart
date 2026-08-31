import 'package:flutter/material.dart';

import '../extensions/context_extensions.dart';

/// Claymorphism/Soft-UI design tokens — colors, radii, and multi-layer
/// shadows for the app's premium visual redesign. Proven first on the
/// Dashboard (see `lib/core/dashboard/presentation`), now the shared design
/// system every screen migrates to, one at a time. Screens not yet migrated
/// keep using the plain Material tokens in `app_colors.dart`/`app_theme.dart`
/// until their own redesign pass.
abstract class AppClay {
  AppClay._();

  // Brand — matches the companion web app's "Ocean blue" identity (its
  // --primary token converts to #165DFC; these are the same blue family,
  // tuned lighter/richer for claymorphism's gradient card surfaces rather
  // than flat UI). Was purple/indigo (#6C63FF) before — that's what read as
  // "not matching the web app" on the Dashboard, the one screen most people
  // see first.
  static const Color primary = Color(0xFF2563EB);
  static const Color secondary = Color(0xFF3B82F6);
  static const Color accent = Color(0xFF7DD3FC);

  // Status — same semantic slots as the app-wide AppColors, re-tuned to the
  // claymorphism palette so cards keep meaning (income=success, expense/
  // overdue=danger, due-soon=warning) without touching the global tokens.
  // Hues nudged toward the web app's own success/expense/warning tokens
  // (#00BC7D / #FB2C36 / #FE9A00) while keeping AppClay's brighter,
  // pastel-leaning character rather than a literal 1:1 copy.
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFF87171);

  /// Alias for money coming in — same value as [success].
  static const Color income = success;

  /// Alias for money going out — same value as [danger].
  static const Color expense = danger;

  /// Three-stop hero gradient — richer than a flat two-color blend so the
  /// hero cards read as lit from one corner rather than a flat fill. Mirrors
  /// the web app's documented "Ocean blue family: navy -> royal -> azure"
  /// gradient language instead of a purple blend.
  static const List<Color> primaryGradient = [Color(0xFF3B82F6), primary, Color(0xFF1D4ED8)];

  static const Color lightBackground = Color(0xFFF6F7FB);
  static const Color darkBackground = Color(0xFF14151D);
  static const Color darkCard = Color(0xFF1E1F29);
  static const Color darkCardAlt = Color(0xFF23242F);

  /// Dark-mode-tuned accent for icon tints/borders/wash gradients that use
  /// [primary] directly. [primary] is a fully-saturated blue calibrated for
  /// contrast against light surfaces; reused as-is on a near-black surface
  /// it reads as an overly vivid "glow" instead of a quiet accent. Matches
  /// the web app's own dark-mode `--primary` (and [AppColors.primaryDark]),
  /// which is deliberately lighter/less saturated for exactly this reason —
  /// standard Material dark-theme practice, just not yet applied to this
  /// color system's small accents.
  static Color primaryAccent(BuildContext context) => context.isDarkMode ? const Color(0xFF629FFF) : primary;

  static Color background(BuildContext context) => context.isDarkMode ? darkBackground : lightBackground;

  static Color card(BuildContext context) => context.isDarkMode ? darkCard : Colors.white;

  /// Subtle top-left-lit gradient fill for standard cards — reads as a
  /// gently domed, softly-lit surface rather than a flat color, the core
  /// claymorphism cue. Falls back to a near-flat dark gradient in dark mode
  /// (a bright highlight would look wrong on a dark surface).
  static LinearGradient cardGradient(BuildContext context) {
    if (context.isDarkMode) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [darkCardAlt, darkCard],
      );
    }
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Colors.white, Color(0xFFF9F8FF)],
    );
  }

  // Radii — flattened to match the app-wide sharp-cornered design language (see
  // AppSizes' matching radius block for the full rationale). [radiusPill] stays a
  // genuine pill/circle shape, left untouched.
  static const double radiusCard = 0;
  static const double radiusLg = 0;
  static const double radiusMd = 0;
  static const double radiusSm = 0;
  static const double radiusPill = 999;

  /// Soft ambient shadow for standard floating cards — three layers (a
  /// wide diffuse ambient layer, a tighter contact layer, and a hint of
  /// warmth from the brand color) so the card reads as resting above the
  /// background rather than merely outlined.
  static List<BoxShadow> soft(BuildContext context) {
    if (context.isDarkMode) {
      return [
        BoxShadow(color: Colors.black.withValues(alpha: 0.42), blurRadius: 28, offset: const Offset(0, 12)),
        BoxShadow(color: Colors.black.withValues(alpha: 0.26), blurRadius: 8, offset: const Offset(0, 3)),
      ];
    }
    return [
      BoxShadow(color: primary.withValues(alpha: 0.10), blurRadius: 36, offset: const Offset(0, 18)),
      BoxShadow(color: const Color(0xFF14171F).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
      BoxShadow(color: Colors.white.withValues(alpha: 0.6), blurRadius: 0, offset: const Offset(0, -1)),
    ];
  }

  /// Stronger, higher-contrast shadow for a screen's hero cards so they
  /// visually float well above every other surface.
  static List<BoxShadow> elevated(BuildContext context) {
    if (context.isDarkMode) {
      return [
        BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 44, offset: const Offset(0, 22)),
        BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
      ];
    }
    return [
      BoxShadow(color: primary.withValues(alpha: 0.28), blurRadius: 48, offset: const Offset(0, 24)),
      BoxShadow(color: primary.withValues(alpha: 0.14), blurRadius: 16, offset: const Offset(0, 6)),
      BoxShadow(color: const Color(0xFF14171F).withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
    ];
  }

  /// Very soft, low-blur shadow for small nested elements (icon chips,
  /// tiles) that shouldn't compete with their parent card's shadow.
  static List<BoxShadow> nested(BuildContext context) {
    if (context.isDarkMode) {
      return [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))];
    }
    return [BoxShadow(color: primary.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 5))];
  }

  /// A soft colored glow behind an icon chip — used sparingly on the most
  /// important accents (hero icons, status icons) rather than on every
  /// small icon, so it stays a highlight, not noise.
  static List<BoxShadow> glow(Color color) {
    return [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))];
  }

  /// Two-stop gradient for a tinted icon chip background — reads as a
  /// small lit orb rather than a flat tinted circle.
  static LinearGradient iconChipGradient(Color color) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.12)],
    );
  }
}
