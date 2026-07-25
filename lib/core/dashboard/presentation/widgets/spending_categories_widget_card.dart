import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/fiscal_year_controller.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../../../features/reports/presentation/providers/category_spending_breakdown_provider.dart';
import '../../../../shared/charts/domain/category_chart_adapters.dart';
import '../../../../shared/widgets/charts/app_pie_chart.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.spendingCategories] — the ranked category
/// breakdown [categorySpendingBreakdownProvider] already computes (a
/// verbatim extraction of what `ReportsScreen` used to compute inline),
/// shown as a pie chart plus a compact top-N list. No category math of its
/// own: every amount/percent traces back to that one shared provider.
class SpendingCategoriesWidgetCard extends ConsumerWidget {
  const SpendingCategoriesWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiscalYearStartMonth = ref.watch(fiscalYearStartMonthProvider);
    final range = config.dateStrategy.resolve(DateTime.now(), fiscalYearStartMonth: fiscalYearStartMonth);
    final period = switch (config.dateStrategy) {
      ReportsPeriodStrategy(:final period) => period,
      _ => ReportsPeriod.custom,
    };
    final entries = ref.watch(categorySpendingBreakdownProvider((range: range, period: period)));
    final textTheme = context.textTheme;
    final colors = context.colors;
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: () => context.push(AppRoutes.reports),
                child: Text('See all ›', style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          if (entries.isEmpty)
            Text('No spending yet.', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))
          else ...[
            Center(child: AppPieChart(data: categorySpendingEntriesToPieData(entries), size: 140)),
            const SizedBox(height: AppSizes.md),
            for (final entry in entries.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: Color(entry.category.colorValue), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(
                        entry.category.name,
                        style: textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Text(format.format(entry.amount), style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
