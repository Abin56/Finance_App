import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
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

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: category.isActive ? 0.15 : 0.06),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Icon(category.icon, color: category.isActive ? color : color.withValues(alpha: 0.4)),
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
        ),
      ),
    );
  }
}
