import 'package:flutter/material.dart';

import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';

/// Shared surface shell for dashboard preview cards (Upcoming Payments,
/// Money to Receive, Spending Snapshot, ...) — the `radiusCard` (24) +
/// [AppShadows.soft] + `lg` padding combination every one of them used to
/// hand-roll separately. Intentionally distinct from the app-wide [AppCard]
/// (`radiusLg`, no shadow): dashboard cards use their own "premium" radius
/// per the Figma spec (see `AppSizes.radiusCard`).
class DashboardSectionCard extends StatelessWidget {
  const DashboardSectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSizes.lg)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
      ),
      padding: padding,
      child: child,
    );
  }
}
