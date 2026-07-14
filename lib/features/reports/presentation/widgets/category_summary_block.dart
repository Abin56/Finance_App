import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';

/// Total / average-per-day / highest-spending-day rollup for a category
/// over the selected period.
class CategorySummaryBlock extends StatelessWidget {
  const CategorySummaryBlock({
    super.key,
    required this.total,
    required this.averagePerDay,
    required this.highestSpendingDay,
    required this.highestSpendingAmount,
  });

  final double total;
  final double averagePerDay;
  final DateTime? highestSpendingDay;
  final double highestSpendingAmount;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Category Summary', style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.md),
          _SummaryRow(label: 'Total Spending', value: CurrencyFormatter.instance.format(total)),
          const SizedBox(height: AppSizes.sm),
          _SummaryRow(label: 'Average per day', value: CurrencyFormatter.instance.format(averagePerDay)),
          const SizedBox(height: AppSizes.sm),
          _SummaryRow(
            label: 'Highest spending day',
            value: highestSpendingDay == null
                ? '—'
                : '${highestSpendingDay!.shortDate} · ${CurrencyFormatter.instance.format(highestSpendingAmount)}',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
        Text(value, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
