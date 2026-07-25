import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/app_bar_chart.dart';
import '../providers/monthly_comparison_provider.dart';

/// Income vs Expense across the last 6 calendar months, via
/// [monthlyComparisonProvider] + the shared [AppBarChart] component — no
/// totals of its own.
class MonthlyComparisonChart extends ConsumerWidget {
  const MonthlyComparisonChart({super.key, this.monthCount = 6});

  final int monthCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(monthlyComparisonProvider(monthCount));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: [
              Text('Monthly Comparison', style: context.textTheme.titleSmall),
              Wrap(
                spacing: AppSizes.md,
                children: [
                  _LegendDot(color: AppColors.income, label: 'Income'),
                  _LegendDot(color: AppColors.expense, label: 'Expense'),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          AppBarChart(data: data),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSizes.xs),
        Text(label, style: context.textTheme.bodySmall),
      ],
    );
  }
}
