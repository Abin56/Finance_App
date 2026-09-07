import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import 'app_text_theme.dart';

/// Builds the app's Material 3 [ThemeData] for both light and dark modes.
///
/// Theme V2 — "Premium Neo-Fintech": rounded, controlled geometry; cards and
/// inputs separated mostly by background + a thin neutral border rather than
/// heavy shadow; the lime brand accent reserved for fills (buttons, selected
/// pills/indicators) and dark-surface accents, never as small text/borders on
/// a light surface (lime is too light-toned to read there — see
/// [AppColors.onLime] and the per-component notes below). All colors flow
/// from [AppColors] so brand updates stay in one place.
abstract class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: AppColors.primaryDark,
            onPrimary: AppColors.onLime,
            secondary: AppColors.secondary,
            onSecondary: Colors.white,
            surface: AppColors.darkSurface,
            onSurface: AppColors.darkTextPrimary,
            surfaceContainerHighest: AppColors.darkSurfaceVariant,
            error: AppColors.error,
            onError: Colors.white,
            outline: AppColors.darkOutline,
          )
        : const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.onLime,
            secondary: AppColors.secondary,
            onSecondary: Colors.white,
            surface: AppColors.lightSurface,
            onSurface: AppColors.lightTextPrimary,
            surfaceContainerHighest: AppColors.lightSurfaceVariant,
            error: AppColors.error,
            onError: Colors.white,
            outline: AppColors.lightOutline,
          );

    final textTheme = buildTextTheme(brightness);
    final background = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final textTertiary = isDark
        ? AppColors.darkTextTertiary
        : AppColors.lightTextTertiary;

    // Plain accent role for text/icons/borders sitting directly on a neutral
    // surface (text buttons, focused-input rings, active nav labels). Lime
    // only has enough contrast when it's a *fill* (button/pill background)
    // or sits on a dark surface — as a thin line or small text on a light
    // surface it all but disappears, so those roles use a dark/near-black
    // accent in light mode and lime itself in dark mode (where it pops).
    final onSurfaceAccent = isDark
        ? AppColors.primaryDark
        : colorScheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      fontFamily: textTheme.bodyMedium?.fontFamily,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: [
        FlowFiColors(
          heroSurface: AppColors.nearBlack,
          heroSurfaceRaised: AppColors.raisedDark,
          onHeroSurface: Colors.white,
          onHeroSurfaceMuted: Colors.white.withValues(alpha: 0.64),
          heroAccent: AppColors.lime,
          onHeroAccent: AppColors.onLime,
          mutedSurface: colorScheme.surfaceContainerHighest,
          border: colorScheme.outline,
          textTertiary: textTertiary,
        ),
      ],

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        surfaceTintColor: Colors.transparent,
      ),

      // Separation comes from a flat surface + thin border, not shadow —
      // "background separation, border, rounded geometry" per the card spec.
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),

      iconTheme: IconThemeData(
        color: colorScheme.onSurface,
        size: AppSizes.iconMd,
      ),

      // Primary CTA — lime fill, near-black foreground (never lime text on a
      // light surface).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.primary.withValues(alpha: 0.4),
          disabledForegroundColor: colorScheme.onPrimary.withValues(alpha: 0.6),
          minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
          elevation: 0,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),

      // Secondary — neutral outlined surface, no brand color.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
          side: BorderSide(color: colorScheme.outline),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),

      // Plain text action — near-black/off-white, not lime (see
      // [onSurfaceAccent]'s doc comment above).
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onSurfaceAccent,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),

      // Light muted fill, subtle border at rest, a bold focus ring (dark in
      // light mode / lime in dark mode, where it reads clearly).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.6 : 1,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: AppSizes.md,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide(color: onSurfaceAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),

      // Interactive filter chip — lime fill + dark text when selected,
      // neutral surface + thin border when not. Status/category badges are a
      // separate, non-interactive widget family (see
      // `lib/shared/widgets/states/`) and don't route through this theme.
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primary,
        labelStyle: textTheme.labelLarge?.copyWith(
          fontSize: 13,
          color: colorScheme.onSurface,
        ),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          fontSize: 13,
          color: colorScheme.onPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          side: BorderSide(color: colorScheme.outline),
        ),
        side: BorderSide(color: colorScheme.outline),
      ),

      // A neutral drag handle (not lime — a thin lime bar reads as an odd
      // decorative accent rather than an affordance, and has weak contrast
      // on a light sheet background); generous top radius per the sheet spec.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurface.withValues(alpha: 0.18),
        dragHandleSize: const Size(40, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSizes.radius2Xl),
          ),
        ),
      ),

      // Dialogs previously fell back to Material 3 defaults — now match the
      // rest of the app's rounded, low-elevation, bordered surface language.
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),

      // Lime pill indicator behind the selected icon, dark icon on top of it
      // (never white-on-lime — insufficient contrast), dark bold label text
      // for the selected tab (not lime — see [onSurfaceAccent]).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        ),
        height: AppSizes.bottomNavHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: AppSizes.iconMd,
            color: states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colorScheme.onSurface : textSecondary,
          );
        }),
      ),

      // The shell's FAB is a bespoke widget (see `app_shell.dart`'s
      // `_GradientFab`, restyled to lime-fill/black-icon) rather than a plain
      // `FloatingActionButton`, but this theme still covers any local FAB a
      // screen builds directly (`ClayFab`/ad-hoc ones being migrated off).
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.nearBlack,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? AppColors.darkTextPrimary : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),

      // Lime header (dark text on top, matching the primary-button
      // convention), a dark "today" ring instead of a thin lime one (weak
      // contrast on the white calendar grid), a soft lime wash for the
      // selected range fill.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: colorScheme.primary,
        headerForegroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        dayShape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          ),
        ),
        todayBorder: BorderSide(color: onSurfaceAccent, width: 1.5),
        rangePickerBackgroundColor: colorScheme.surface,
        rangeSelectionBackgroundColor: colorScheme.primary.withValues(
          alpha: 0.18,
        ),
        yearShape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          ),
        ),
      ),
    );
  }
}

/// Custom FlowFi tokens that Material's [ColorScheme] can't represent
/// cleanly — the dark "hero" financial-surface family (balance/summary
/// cards, premium account/credit-card visuals) and a couple of extra neutral
/// steps ([textTertiary], [mutedSurface]) the app's tile/badge widgets need.
/// Access via `Theme.of(context).extension<FlowFiColors>()!` (or
/// `context.flowfi`, see `context_extensions.dart`).
@immutable
class FlowFiColors extends ThemeExtension<FlowFiColors> {
  const FlowFiColors({
    required this.heroSurface,
    required this.heroSurfaceRaised,
    required this.onHeroSurface,
    required this.onHeroSurfaceMuted,
    required this.heroAccent,
    required this.onHeroAccent,
    required this.mutedSurface,
    required this.border,
    required this.textTertiary,
  });

  /// Near-black surface for the dashboard's total-balance card, account/
  /// credit-card visuals, and other high-emphasis financial surfaces.
  final Color heroSurface;

  /// One step lighter than [heroSurface] — a nested element resting on a
  /// hero surface (e.g. a stat row inside the balance card).
  final Color heroSurfaceRaised;

  final Color onHeroSurface;

  /// A dimmed variant of [onHeroSurface] for supporting text on the hero
  /// surface (e.g. "Total balance" under the big number).
  final Color onHeroSurfaceMuted;

  /// The lime accent as it appears *on a hero surface* — small markers,
  /// progress fills, an accent icon — where it has excellent contrast,
  /// unlike on a light surface.
  final Color heroAccent;
  final Color onHeroAccent;

  /// A muted neutral surface for the "soft secondary card" family (grouped
  /// stats/controls) — same value as `ColorScheme.surfaceContainerHighest`,
  /// exposed here so callers don't need to reach into both places.
  final Color mutedSurface;

  final Color border;

  /// A third text tier below primary/secondary — timestamps, unit labels,
  /// the quietest text on a row.
  final Color textTertiary;

  @override
  FlowFiColors copyWith({
    Color? heroSurface,
    Color? heroSurfaceRaised,
    Color? onHeroSurface,
    Color? onHeroSurfaceMuted,
    Color? heroAccent,
    Color? onHeroAccent,
    Color? mutedSurface,
    Color? border,
    Color? textTertiary,
  }) {
    return FlowFiColors(
      heroSurface: heroSurface ?? this.heroSurface,
      heroSurfaceRaised: heroSurfaceRaised ?? this.heroSurfaceRaised,
      onHeroSurface: onHeroSurface ?? this.onHeroSurface,
      onHeroSurfaceMuted: onHeroSurfaceMuted ?? this.onHeroSurfaceMuted,
      heroAccent: heroAccent ?? this.heroAccent,
      onHeroAccent: onHeroAccent ?? this.onHeroAccent,
      mutedSurface: mutedSurface ?? this.mutedSurface,
      border: border ?? this.border,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  FlowFiColors lerp(ThemeExtension<FlowFiColors>? other, double t) {
    if (other is! FlowFiColors) return this;
    return FlowFiColors(
      heroSurface: Color.lerp(heroSurface, other.heroSurface, t)!,
      heroSurfaceRaised: Color.lerp(
        heroSurfaceRaised,
        other.heroSurfaceRaised,
        t,
      )!,
      onHeroSurface: Color.lerp(onHeroSurface, other.onHeroSurface, t)!,
      onHeroSurfaceMuted: Color.lerp(
        onHeroSurfaceMuted,
        other.onHeroSurfaceMuted,
        t,
      )!,
      heroAccent: Color.lerp(heroAccent, other.heroAccent, t)!,
      onHeroAccent: Color.lerp(onHeroAccent, other.onHeroAccent, t)!,
      mutedSurface: Color.lerp(mutedSurface, other.mutedSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}
