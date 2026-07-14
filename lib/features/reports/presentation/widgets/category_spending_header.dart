import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../categories/domain/category.dart';

/// Category icon, name, total spent, and its share of overall expenses for
/// the selected period — the summary block atop the category detail screen.
class CategorySpendingHeader extends StatelessWidget {
  const CategorySpendingHeader({super.key, required this.category, required this.total, required this.percentOfTotal});

  final Category category;
  final double total;
  final double percentOfTotal;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(category.icon, color: color, size: AppSizes.iconLg),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category.name, style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.xs),
              Text(
                CurrencyFormatter.instance.format(total),
                style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                '${(percentOfTotal * 100).toStringAsFixed(1)}% of total expenses',
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
