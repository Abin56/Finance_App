import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../theme/clay_theme.dart';

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
    return AnimatedScale(
      scale: _pressed && widget.onTap != null ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      // The shadow lives on this outer, unclipped box: putting it on the
      // same layer as the rounded-corner clip below would crop the blur
      // off entirely, which is why these cards used to read as flat.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppClay.radiusCard),
          boxShadow: AppClay.soft(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppClay.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: Ink(
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                gradient: widget.backgroundColor == null ? AppClay.cardGradient(context) : null,
              ),
              padding: widget.padding ??
                  (widget.isHero
                      ? const EdgeInsets.all(AppSizes.md)
                      : const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm)),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Net-Worth-style hero variant — same radius/shadow, filled with the
/// brand gradient instead of a plain surface color. Also carries two soft,
/// blurred decorative "orbs" — a claymorphism/ambient-lighting cue rather
/// than a flat gradient fill, kept subtle enough not to fight the content.
class DashboardWidgetGradientCard extends StatefulWidget {
  const DashboardWidgetGradientCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<DashboardWidgetGradientCard> createState() => _DashboardWidgetGradientCardState();
}

class _DashboardWidgetGradientCardState extends State<DashboardWidgetGradientCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed && widget.onTap != null ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      // Shadow on the outer, unclipped box — see the note in
      // [DashboardWidgetCard] for why this can't live on the clipped layer.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppClay.radiusCard),
          boxShadow: AppClay.elevated(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppClay.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: AppClay.primaryGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  const Positioned(top: -30, right: -30, child: _Orb(size: 130, opacity: 0.16)),
                  const Positioned(bottom: -46, left: -20, child: _Orb(size: 120, opacity: 0.12)),
                  widget.child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Colors.white.withValues(alpha: opacity), Colors.white.withValues(alpha: 0)],
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
    return Opacity(
      opacity: isVisible ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppClay.radiusCard),
          border: Border.all(color: AppClay.primaryAccent(context), width: 1.5, style: BorderStyle.solid),
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
                    icon: Icon(isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
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
