import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/fiscal_year_controller.dart';
import '../../../../features/categories/presentation/providers/category_providers.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../../../features/reports/presentation/providers/category_spending_breakdown_provider.dart';
import '../../../../features/reports/presentation/widgets/reports_category_list.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../../shared/charts/domain/category_chart_adapters.dart';
import '../../../../shared/charts/domain/pie_chart_data.dart';
import '../../../../shared/widgets/charts/app_pie_chart.dart';
import '../../../../shared/widgets/states/section_load_state.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import '../providers/dashboard_display_providers.dart';
import 'dashboard_format.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.spendingCategories] — the ranked category
/// breakdown [categorySpendingBreakdownProvider] already computes (my share
/// of each expense, the same provider Reports uses), as a donut beside the
/// top five categories with the rest folded into one "Others" row. No
/// category math of its own: every amount/percent traces back to that one
/// shared provider; "Others" is only the sum of the rows it replaces.
class SpendingCategoriesWidgetCard extends ConsumerWidget {
  const SpendingCategoriesWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  static const _topN = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiscalYearStartMonth = ref.watch(fiscalYearStartMonthProvider);
    final range = config.dateStrategy.resolve(
      DateTime.now(),
      fiscalYearStartMonth: fiscalYearStartMonth,
    );
    final period = switch (config.dateStrategy) {
      ReportsPeriodStrategy(:final period) => period,
      _ => ReportsPeriod.custom,
    };
    final subtitle = switch (config.dateStrategy) {
      ReportsPeriodStrategy(:final period)
          when period != ReportsPeriod.custom =>
        period.label,
      _ => '${range.start.shortDate} – ${range.end.shortDate}',
    };
    final load = SectionLoad.of([
      ref.watch(transactionsStreamProvider),
      ref.watch(categoriesStreamProvider),
      ref.watch(expensesStreamProvider),
    ]);

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            title: config.title,
            subtitle: '$subtitle · your share',
            actionLabel: 'Report',
            onAction: () => context.push(AppRoutes.reports),
          ),
          const SizedBox(height: AppSizes.sm),
          DashboardSectionBody(
            load: load,
            errorMessage: "Couldn't load your spending.",
            onRetry: () => invalidateDashboardSources(ref),
            builder: (context) {
              final entries = ref.watch(
                categorySpendingBreakdownProvider((
                  range: range,
                  period: period,
                )),
              );
              if (entries.isEmpty) {
                return const DashboardEmptyLine(
                  icon: Icons.pie_chart_outline_rounded,
                  message: 'No spending in this period yet.',
                );
              }
              return _CategoryBreakdown(entries: entries);
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.entries});

  final List<CategorySpendingEntry> entries;

  @override
  Widget build(BuildContext context) {
    final top = entries.take(SpendingCategoriesWidgetCard._topN).toList();
    final rest = entries.skip(SpendingCategoriesWidgetCard._topN);
    final restAmount = rest.fold(0.0, (s, e) => s + e.amount);
    final restShare = rest.fold(0.0, (s, e) => s + e.percentOfTotal);
    final total = entries.fold(0.0, (s, e) => s + e.amount);
    final colors = context.colors;
    final othersColor = colors.onSurfaceVariant.withValues(alpha: 0.5);

    final rows = [
      for (final e in top)
        _CategoryRow(
          color: Color(e.category.colorValue),
          name: e.category.name,
          amount: e.amount,
          share: e.percentOfTotal,
        ),
      if (restAmount > 0)
        _CategoryRow(
          color: othersColor,
          name: 'Others (${rest.length})',
          amount: restAmount,
          share: restShare,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final chart = Stack(
          alignment: Alignment.center,
          children: [
            // Same slices as the legend (top five + one Others slice), with
            // no on-slice labels: the legend carries the percentages.
            AppPieChart(
              data: AppPieChartData(
                slices: [
                  ...categorySpendingEntriesToPieData(top).slices,
                  if (restAmount > 0)
                    ChartSlice(
                      label: 'Others',
                      value: restAmount,
                      color: othersColor,
                    ),
                ],
              ),
              size: 112,
              showSliceLabels: false,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatRupeesCompact(total),
                  style: context.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'spent',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        );
        // Side-by-side when there's room; stacked on narrow phones / large
        // text so names and amounts never get squeezed.
        if (constraints.maxWidth >= 340) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              chart,
              const SizedBox(width: AppSizes.lg),
              Expanded(child: Column(children: rows)),
            ],
          );
        }
        return Column(
          children: [
            Center(child: chart),
            const SizedBox(height: AppSizes.md),
            ...rows,
          ],
        );
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.color,
    required this.name,
    required this.amount,
    required this.share,
  });

  final Color color;
  final String name;
  final double amount;

  /// 0–1 share of the period's total.
  final double share;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              name,
              style: textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSizes.xs),
          Text(
            '${(share * 100).round()}%',
            style: textTheme.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            formatRupeesCompact(amount),
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
