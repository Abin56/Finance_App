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
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
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
        ],
      ),
    );
  }
}
