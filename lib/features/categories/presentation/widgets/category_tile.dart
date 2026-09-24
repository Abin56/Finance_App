import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/flowfi_card.dart';
import '../../../../shared/widgets/lists/flowfi_list_tile.dart';
import '../../../../shared/widgets/states/flowfi_icon_chip.dart';
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

    return FlowFiCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: FlowFiListTile(
        leading: FlowFiIconChip(
          icon: category.icon,
          color: category.isActive ? color : color.withValues(alpha: 0.4),
          size: 44,
          iconSize: AppSizes.iconMd,
        ),
        title: Text(
          category.name,
          style: context.textTheme.titleMedium?.copyWith(
            color: category.isActive
                ? null
                : context.colors.onSurface.withValues(alpha: 0.4),
          ),
        ),
        subtitle: Text(
          category.type.label,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.flowfi.textTertiary,
          ),
        ),
        trailing: category.isDefault
            ? Text(
                'Default',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.4),
                ),
              )
            : null,
        trailingSubtitle: !category.isActive
            ? Text(
                'Inactive',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.error,
                ),
              )
            : null,
      ),
    );
  }
}
