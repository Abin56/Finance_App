import 'package:flutter/material.dart';

import '../../../core/constants/app_shadows.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';

/// The three Theme V2 card families, as one widget. Replaces the old
/// claymorphism `ClayCard` (gradients + layered shadow) and the ad-hoc
/// `Material`/`Container` shells feature screens built individually —
/// separation now comes mostly from background + a thin border + rounded
/// geometry, not heavy shadow, per the "Premium Neo-Fintech" card spec.
///
/// - [FlowFiCard] (default) — standard content card: white/light surface,
///   thin neutral border, no shadow.
/// - [FlowFiCard.hero] — the dark financial hero surface: near-black
///   background, white text, optional lime accent bar. For a screen's single
///   most important financial summary (total balance, credit exposure) —
///   use at most one per screen.
/// - [FlowFiCard.soft] — a muted secondary surface for grouped stats/
///   controls that shouldn't compete visually with a standard or hero card.
class FlowFiCard extends StatelessWidget {
  const FlowFiCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.radius = AppSizes.radiusLg,
  }) : _variant = _FlowFiCardVariant.standard,
       _showAccent = false;

  const FlowFiCard.hero({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSizes.xl),
    this.radius = AppSizes.radiusCard,
    bool accent = false,
  }) : _variant = _FlowFiCardVariant.hero,
       _showAccent = accent;

  const FlowFiCard.soft({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.radius = AppSizes.radiusLg,
  }) : _variant = _FlowFiCardVariant.soft,
       _showAccent = false;

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final _FlowFiCardVariant _variant;

  /// [FlowFiCard.hero] only — draws a thin lime bar along the top edge, for
  /// the one hero card on a screen that should carry the brand accent.
  final bool _showAccent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final flowfi = context.flowfi;
    final borderRadius = BorderRadius.circular(radius);

    final (
      Color background,
      Border? border,
      List<BoxShadow>? shadow,
    ) = switch (_variant) {
      _FlowFiCardVariant.standard => (
        colors.surface,
        Border.all(color: colors.outline),
        null,
      ),
      _FlowFiCardVariant.soft => (flowfi.mutedSurface, null, null),
      _FlowFiCardVariant.hero => (
        flowfi.heroSurface,
        null,
        AppShadows.elevated(context),
      ),
    };

    Widget content = Padding(padding: padding, child: child);

    if (_variant == _FlowFiCardVariant.hero) {
      content = DefaultTextStyle.merge(
        style: TextStyle(color: flowfi.onHeroSurface),
        child: IconTheme.merge(
          data: IconThemeData(color: flowfi.onHeroSurface),
          child: content,
        ),
      );
      if (_showAccent) {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: flowfi.heroAccent,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                ),
              ),
            ),
            content,
          ],
        );
      }
    }

    return Container(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
      child: Material(
        color: background,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: border,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

enum _FlowFiCardVariant { standard, soft, hero }
