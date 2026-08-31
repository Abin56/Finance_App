import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../domain/category.dart';
import '../../domain/category_type.dart';

/// Row for a single category, swipeable to soft-delete (handled by the
/// screen that owns the Dismissible key, same as [AccountTile]).
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);

    return ClayCard(
      onTap: onTap,
      child: Row(
        children: [
          ClayIconChip(
            icon: category.icon,
            color: category.isActive ? color : color.withValues(alpha: 0.4),
            size: 44,
            iconSize: AppSizes.iconMd,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: category.isActive ? null : context.colors.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  category.type.label,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (category.isDefault)
            Padding(
              padding: const EdgeInsets.only(left: AppSizes.sm),
              child: Text(
                'Default',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          if (!category.isActive)
            Padding(
              padding: const EdgeInsets.only(left: AppSizes.sm),
              child: Text(
                'Inactive',
                style: context.textTheme.labelSmall?.copyWith(color: context.colors.error),
              ),
            ),
        ],
      ),
    );
  }
}
