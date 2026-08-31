import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';

/// Flat, borderless surface for quiet/secondary grouped content (list rows,
/// form sections) — deliberately plainer than `ClayCard`'s floating shadow
/// treatment, mirroring the web app's `.surface-secondary`/`.surface-tertiary`
/// tiers: not every card is a hero, some are meant to recede. Wraps [InkWell]
/// so any card can be tappable without callers re-implementing ripple + radius.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.color,
    this.radius = AppSizes.radiusLg,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return Material(
      color: color ?? context.colors.surface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
