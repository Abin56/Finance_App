import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/charts/domain/category_chart_adapters.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/app_pie_chart.dart';
import 'reports_category_list.dart';

/// Pie-chart view of the same [CategorySpendingEntry] list
/// [ReportsCategoryList] already renders as a ranked list — additive, not a
/// replacement: the list stays the primary drill-down UI, this is a
/// glanceable breakdown above it. Uses [categorySpendingEntriesToPieData]
/// to adapt the existing entries rather than a second category shape.
class CategorySpendingPieChart extends StatelessWidget {
  const CategorySpendingPieChart({super.key, required this.entries});

  final List<CategorySpendingEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final top = entries.take(6).toList();

    return AppCard(
      child: Row(
        children: [
          AppPieChart(data: categorySpendingEntriesToPieData(top), size: 120),
          const SizedBox(width: AppSizes.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: Color(entry.category.colorValue), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: AppSizes.xs),
                        Expanded(
                          child: Text(
                            entry.category.name,
                            style: context.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSizes.xs),
                        Text(
                          CurrencyFormatter.instance.formatCompact(entry.amount),
                          style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
