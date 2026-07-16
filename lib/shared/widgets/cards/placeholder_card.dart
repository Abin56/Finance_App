import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/extensions/context_extensions.dart';
import 'app_card.dart';

/// Shared empty-state shell used by any feature's dashboard-style section
/// that has nothing to show yet — an icon, a title, a short message, and
/// an optional tap-through to go set the underlying feature up.
class PlaceholderCard extends StatelessWidget {
  const PlaceholderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onTap,
    this.actionLabel,
    this.radius = AppSizes.radiusLg,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onTap;

  /// Visible call-to-action ("Set a budget", "Add a transaction", ...) shown
  /// under the message and wired to the same [onTap] — without this, an
  /// empty card's only affordance is an invisible whole-card tap target.
  final String? actionLabel;

  /// Corner radius override — dashboard callers pass [AppSizes.radiusCard]
  /// to match their loaded-state siblings, since this wraps [AppCard]'s
  /// default [AppSizes.radiusLg] otherwise.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      radius: radius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: AppSizes.iconMd, color: context.colors.onSurface.withValues(alpha: 0.5)),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  message,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSizes.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  actionLabel!,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: context.colors.primary),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
