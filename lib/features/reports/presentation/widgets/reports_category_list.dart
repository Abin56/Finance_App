import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../categories/domain/category.dart';

class CategorySpendingEntry {
  const CategorySpendingEntry({required this.category, required this.amount, required this.percentOfTotal});

  final Category category;
  final double amount;
  final double percentOfTotal;
}

/// Ranked list of categories with a colored icon, amount, and a progress
/// bar sized to each category's share of total spending — tapping a row
/// opens that category's detail screen.
class ReportsCategoryList extends StatelessWidget {
  const ReportsCategoryList({super.key, required this.entries, required this.onTapCategory});

  final List<CategorySpendingEntry> entries;
  final void Function(Category category) onTapCategory;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSizes.md),
          _CategoryRow(entry: entries[i], onTap: () => onTapCategory(entries[i].category)),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.entry, required this.onTap});

  final CategorySpendingEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(entry.category.colorValue);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(entry.category.icon, color: color, size: AppSizes.iconMd),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.category.name, style: context.textTheme.bodyLarge),
                      Text(
                        CurrencyFormatter.instance.format(entry.amount),
                        style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Row(
                    children: [
                      Expanded(child: ProgressBar(progress: entry.percentOfTotal, height: 6)),
                      const SizedBox(width: AppSizes.sm),
                      Text(
                        '${(entry.percentOfTotal * 100).toStringAsFixed(1)}%',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
