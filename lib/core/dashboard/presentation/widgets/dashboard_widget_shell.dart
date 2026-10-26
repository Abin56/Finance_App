import 'package:flutter/material.dart';

import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/states/section_load_state.dart';

/// The one header every Dashboard 2.0 section uses: title, an optional
/// quiet subtitle (the period or a count), and an optional trailing action
/// rendered as a real button — 48×40 hit target, ink feedback and button
/// semantics, unlike the old bare `GestureDetector` "See all ›" text.
class DashboardCardHeader extends StatelessWidget {
  const DashboardCardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: textTheme.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.onSurface,
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
              textStyle: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!),
                const Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm),
              ],
            ),
          ),
      ],
    );
  }
}

/// Renders [builder] only once [load] is ready — a skeleton while the
/// section's streams are still loading and an honest error row (with Retry)
/// when one failed, so neither state is ever drawn as "empty" or ₹0.
class DashboardSectionBody extends StatelessWidget {
  const DashboardSectionBody({
    super.key,
    required this.load,
    required this.builder,
    this.onRetry,
    this.errorMessage = "Couldn't load this section.",
    this.skeletonRows = 3,
    this.skeletonLeadingHeight = 0,
  });

  final SectionLoad load;
  final WidgetBuilder builder;
  final VoidCallback? onRetry;
  final String errorMessage;
  final int skeletonRows;
  final double skeletonLeadingHeight;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (load.status) {
      SectionLoadStatus.loading => SectionSkeleton(
        key: const ValueKey('loading'),
        rows: skeletonRows,
        leadingHeight: skeletonLeadingHeight,
      ),
      SectionLoadStatus.error => SectionErrorRow(
        key: const ValueKey('error'),
        message: errorMessage,
        onRetry: onRetry,
      ),
      SectionLoadStatus.ready => KeyedSubtree(
        key: const ValueKey('ready'),
        child: builder(context),
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

/// A calm one-line empty state with an optional next step — used inside a
/// section instead of a bare grey sentence.
class DashboardEmptyLine extends StatelessWidget {
  const DashboardEmptyLine({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconSm, color: colors.onSurfaceVariant),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Text(
            message,
            style: context.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            // Lime text fails contrast on a light surface — CTAs on plain
            // surfaces take the primary text color instead.
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              minimumSize: const Size(48, 40),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// Shared surface shell every dashboard widget card renders inside — same
/// radius/shadow contract as the old `DashboardSectionCard`, just promoted
/// out of the `dashboard` feature so the new widget-based architecture
/// (living under `core/dashboard`) doesn't depend back on it.
class DashboardWidgetCard extends StatefulWidget {
  const DashboardWidgetCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.backgroundColor,
    this.showHairline = true,
    this.isHero = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Overrides the default gradient fill — used by cards that need a
  /// semantic tint (e.g. the warning-tinted Previous Cycle card) without
  /// every card re-implementing its own [Material]/[Container].
  final Color? backgroundColor;

  /// Whether to draw the subtle 1px outline Apple-style cards use alongside
  /// their shadow for definition on light, low-contrast backgrounds. Off by
  /// default for tinted cards where a hairline would fight the tint.
  final bool showHairline;

  /// Widens internal padding to the hero rhythm for the dashboard's largest,
  /// most prominent cards. Non-hero cards use a tighter vertical rhythm than
  /// horizontal — Apple Wallet/Fitness-style compact spacing — since card
  /// content is almost always wider than it is tall.
  final bool isHero;

  @override
  State<DashboardWidgetCard> createState() => _DashboardWidgetCardState();
}

class _DashboardWidgetCardState extends State<DashboardWidgetCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Tinted cards (credit utilization, previous-cycle) opt out of the
    // hairline via [showHairline] so their semantic wash isn't undercut by a
    // competing neutral border.
    final border = widget.showHairline
        ? Border.all(color: colors.outline)
        : null;

    return AnimatedScale(
      scale: _pressed && widget.onTap != null ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      // The shadow lives on this outer, unclipped box: putting it on the
      // same layer as the rounded-corner clip below would crop the blur
      // off entirely, which is why these cards used to read as flat.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusCard),
          boxShadow: AppShadows.soft(context),
        ),
        child: Material(
          color: widget.backgroundColor ?? colors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: Container(
              // The radius keeps the hairline's corners from being cut off by
              // the Material's rounded clip.
              decoration: BoxDecoration(
                border: border,
                borderRadius: BorderRadius.circular(AppSizes.radiusCard),
              ),
              padding:
                  widget.padding ??
                  (widget.isHero
                      ? const EdgeInsets.all(AppSizes.lg)
                      : const EdgeInsets.fromLTRB(
                          AppSizes.lg,
                          AppSizes.md,
                          AppSizes.lg,
                          AppSizes.md,
                        )),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps any widget card with Edit Mode chrome — drag handle, settings,
/// visibility toggle, delete — without the card itself knowing Edit Mode
/// exists. The dashboard shell decides whether to wrap a card in this or
/// render it plain, so every widget builder only ever renders its View Mode
/// content.
class DashboardWidgetEditFrame extends StatelessWidget {
  const DashboardWidgetEditFrame({
    super.key,
    required this.title,
    required this.child,
    required this.isVisible,
    required this.onToggleVisibility,
    required this.onConfigure,
    required this.onDelete,
    this.dragHandle,
    this.canConfigure = true,
  });

  final String title;
  final Widget child;
  final bool isVisible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final Widget? dragHandle;

  /// Whether this widget has settings — a settings button that does nothing
  /// is not shown.
  final bool canConfigure;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Same dark-in-light/lime-in-dark accent rule `app_theme.dart` uses for
    // focus rings — a thin lime outline reads poorly against a light card,
    // so light mode borrows near-black instead and dark mode gets the lime
    // pop.
    final accent = context.isDarkMode
        ? context.flowfi.heroAccent
        : colors.onSurface;
    return Opacity(
      opacity: isVisible ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusCard),
          border: Border.all(
            color: accent,
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        padding: const EdgeInsets.all(AppSizes.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
              child: Row(
                children: [
                  ?dragHandle,
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: context.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canConfigure)
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      iconSize: AppSizes.iconSm,
                      onPressed: onConfigure,
                      tooltip: 'Configure',
                    ),
                  IconButton(
                    icon: Icon(
                      isVisible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    iconSize: AppSizes.iconSm,
                    onPressed: onToggleVisibility,
                    tooltip: isVisible ? 'Hide' : 'Show',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: AppSizes.iconSm,
                    color: colors.error,
                    onPressed: onDelete,
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            IgnorePointer(child: child),
          ],
        ),
      ),
    );
  }
}
