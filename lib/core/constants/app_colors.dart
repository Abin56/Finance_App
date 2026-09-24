import 'package:flutter/material.dart';

/// Centralized color palette for the app, used to build both
/// the light and dark [ColorScheme]s in `app_theme.dart`.
///
/// Theme V2 — "Premium Neo-Fintech": an electric-lime brand accent over a
/// warm-neutral light canvas / near-black dark canvas, replacing the old
/// Ocean-blue (`#165DFC`) brand and the claymorphism blue (`AppClay`,
/// `#2563EB`) so the app has one brand identity instead of two competing
/// ones. Financial semantic colors (income/expense/pending/info) are left
/// unchanged from their web-app-matched values — they were already correct
/// and distinct, only the *brand* colors needed retiring.
abstract class AppColors {
  AppColors._();

  // Brand — electric lime, used sparingly for CTAs, selected/active states,
  // and focus/progress accents (see [onLime] for the foreground that goes
  // on top of it). Two strengths: [lime] for larger fills/washes, [limeStrong]
  // for the primary/CTA role, which needs a touch more saturation to read as
  // "the button" rather than a soft highlight.
  static const Color lime = Color(0xFFB9F65A);
  static const Color limeStrong = Color(0xFFA8EC35);

  /// Near-black foreground for content sitting on a lime fill — lime is too
  /// light for white text to be legible, so every on-lime label/icon uses
  /// this instead (mirrors [ColorScheme.onPrimary]).
  static const Color onLime = Color(0xFF14150F);

  /// The dark "hero" surface tone — used for the financial hero card
  /// (balance/summary), premium credit-card visuals, and other
  /// high-emphasis surfaces, in both light and dark mode.
  static const Color nearBlack = Color(0xFF171817);

  /// One step up from [nearBlack] — a dark card resting on another dark
  /// surface (e.g. a nested tile inside a hero card).
  static const Color raisedDark = Color(0xFF222321);

  static const Color primary = limeStrong;
  static const Color primaryDark = lime;

  /// Secondary brand accent — teal, used for chart-series variety and a
  /// handful of icon accents. Deliberately not lime (lime stays reserved
  /// for primary/selected/CTA per the color-usage rule) and not blue (the
  /// retired brand color).
  static const Color secondary = Color(0xFF00C2A8);

  /// Matches the web app's `--purple` token — a semantic accent for
  /// tags/badges that need a color outside the money-direction palette.
  static const Color purple = Color(0xFF8E51FF);

  /// Icon-tint accents for the More/Settings menu rows that don't map to an
  /// existing semantic color (People, EMIs) — named once here instead of
  /// being redeclared as raw hex literals at each call site. Values match
  /// the existing [categoryPalette] pink/blue swatches; the matching purple
  /// row uses [purple] directly rather than a near-duplicate separate shade.
  static const Color menuAccentPink = Color(0xFFE85D9A);
  static const Color menuAccentBlue = Color(0xFF40C4FF);

  // Semantic — matches the web app's `--success`/`--expense`/`--warning`
  // tokens. Unchanged by the Theme V2 migration: these already read as
  // distinct, accessible green/red/amber/blue and must keep indicating
  // meaning (income vs expense vs pending), not brand.
  static const Color income = Color(0xFF00BC7D);
  static const Color expense = Color(0xFFFB2C36);
  static const Color pending = Color(0xFFFE9A00);
  static const Color savings = Color(0xFF3E8EFF);
  static const Color credit = Color(0xFF00BC7D);
  static const Color debit = Color(0xFFFB2C36);

  // Light surfaces — warm/neutral off-white canvas, crisp white cards.
  static const Color lightBackground = Color(0xFFF5F6F3);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF0F2EF);
  static const Color lightOutline = Color(0xFFE4E7E2);

  // Dark surfaces — intentionally near-black rather than pure #000, with a
  // deliberate canvas -> surface -> elevated-surface step (not a flat invert
  // of the light palette).
  static const Color darkBackground = Color(0xFF121310);
  static const Color darkSurface = Color(0xFF1B1C19);
  static const Color darkSurfaceVariant = Color(0xFF222321);
  static const Color darkOutline = Color(0xFF34362E);

  // Text
  static const Color lightTextPrimary = Color(0xFF151715);
  static const Color lightTextSecondary = Color(0xFF686C67);
  static const Color lightTextTertiary = Color(0xFF979B96);
  static const Color darkTextPrimary = Color(0xFFF2F3EF);
  static const Color darkTextSecondary = Color(0xFF9A9D96);
  static const Color darkTextTertiary = Color(0xFF75786F);

  // Status — same values as the semantic tokens above, kept as their own
  // names since call sites reference `AppColors.error`/`.warning`/`.info`
  // independently of the money-direction ones.
  static const Color success = Color(0xFF00BC7D);
  static const Color warning = Color(0xFFFE9A00);
  static const Color error = Color(0xFFFB2C36);
  static const Color info = Color(0xFF3E8EFF);

  // Category palette (used as default colors when creating custom categories)
  // — first swatch matches [primary] so the default pick stays on-brand.
  static const List<Color> categoryPalette = [
    Color(0xFFA8EC35),
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

  // Card-face tint swatches offered when personalizing a credit card's
  // visual (`CreditCardFormSheet`'s step 4 "Card color" picker and
  // `AddCardToSharedLimitSheet`'s matching picker for a second physical
  // card). A bank-card face wants more — and more muted/metallic — options
  // (silver, gold, slate) than [categoryPalette]'s brighter category
  // swatches, so this is its own list rather than reusing that one. Both
  // sheets used to each hardcode an identical (or near-identical, one being
  // a truncated copy of the other) local `_cardThemeColors` literal; this is
  // the single source both now reference instead.
  static const List<Color> cardTintPalette = [
    Color(0xFF1565C0), // blue
    Color(0xFF212121), // black
    Color(0xFF6A1B9A), // purple
    Color(0xFF2E7D32), // green
    Color(0xFFC62828), // red
    Color(0xFF78909C), // silver
    Color(0xFFB8860B), // gold
    Color(0xFF00695C), // teal
    Color(0xFFAD1457), // pink
    Color(0xFFEF6C00), // orange
    Color(0xFF4527A0), // indigo
    Color(0xFF00838F), // cyan
    Color(0xFF558B2F), // olive
    Color(0xFF5D4037), // brown
    Color(0xFF37474F), // slate
    Color(0xFFF9A825), // amber
  ];

  // Gradients — kept minimal per Theme V2's "very limited gradient usage"
  // rule. [primaryGradient] is now a subtle near-black hero wash (not a
  // brand-blue fill) for the rare dark hero surface that wants a lit-corner
  // treatment instead of a flat fill; [incomeGradient]/[savingsGradient]
  // stay semantic-toned for the few small progress/chart accents that used
  // them before.
  static const List<Color> primaryGradient = [Color(0xFF2A2C27), nearBlack];
  static const List<Color> incomeGradient = [
    Color(0xFF00BC7D),
    Color(0xFF0E9F6E),
  ];
  static const List<Color> savingsGradient = [
    Color(0xFF3E8EFF),
    Color(0xFF165DFC),
  ];
}
