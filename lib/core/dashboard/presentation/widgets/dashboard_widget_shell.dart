import 'package:flutter/material.dart';

import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

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
              decoration: BoxDecoration(border: border),
              padding:
                  widget.padding ??
                  (widget.isHero
                      ? const EdgeInsets.all(AppSizes.md)
                      : const EdgeInsets.symmetric(
                          horizontal: AppSizes.md,
                          vertical: AppSizes.sm,
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
  });

  final String title;
  final Widget child;
  final bool isVisible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final Widget? dragHandle;

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
