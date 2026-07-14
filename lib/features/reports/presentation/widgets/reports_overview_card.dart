import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';

/// Total income / total expenses / net savings for the selected period,
/// each with a percent change vs. the prior comparable period.
class ReportsOverviewCard extends StatelessWidget {
  const ReportsOverviewCard({
    super.key,
    required this.income,
    required this.expenses,
    required this.incomeChangePercent,
    required this.expensesChangePercent,
    required this.netSavingsChangePercent,
  });

  final double income;
  final double expenses;
  final double? incomeChangePercent;
  final double? expensesChangePercent;
  final double? netSavingsChangePercent;

  @override
  Widget build(BuildContext context) {
    final netSavings = income - expenses;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _OverviewStat(
              label: 'Total Income',
              value: income,
              valueColor: AppColors.income,
              changePercent: incomeChangePercent,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: _OverviewStat(
              label: 'Total Expenses',
              value: expenses,
              valueColor: AppColors.expense,
              changePercent: expensesChangePercent,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: _OverviewStat(
              label: 'Net Savings',
              value: netSavings,
              valueColor: context.colors.onSurface,
              changePercent: netSavingsChangePercent,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.changePercent,
  });

  final String label;
  final double value;
  final Color valueColor;
  final double? changePercent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: valueColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (changePercent != null) ...[
          const SizedBox(height: AppSizes.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                changePercent! >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: AppSizes.iconSm,
                color: changePercent! >= 0 ? AppColors.income : AppColors.expense,
              ),
              Text(
                '${changePercent!.abs().round()}%',
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: changePercent! >= 0 ? AppColors.income : AppColors.expense,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
