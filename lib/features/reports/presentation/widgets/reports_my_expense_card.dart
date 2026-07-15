import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../expense/presentation/providers/expense_providers.dart';

/// Task 7's split-share-aware Reports section — every figure here is
/// derived from `Expense.myShare` (never the full transaction amount), for
/// the selected period. Mirrors `ReportsOverviewCard`'s layout so Reports
/// reads consistently across sections.
class ReportsMyExpenseCard extends StatelessWidget {
  const ReportsMyExpenseCard({
    super.key,
    required this.breakdown,
    required this.moneyToReceive,
    required this.moneyReceived,
  });

  final MyExpenseBreakdown breakdown;

  final double moneyToReceive;
  final double moneyReceived;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _Stat(label: 'My Total Expense', value: breakdown.total)),
              const SizedBox(width: AppSizes.md),
              Expanded(child: _Stat(label: 'Personal Expense', value: breakdown.personal)),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(child: _Stat(label: 'Split Expense', value: breakdown.split)),
              const SizedBox(width: AppSizes.md),
              Expanded(child: _Stat(label: 'Money To Receive', value: moneyToReceive, color: AppColors.pending)),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(child: _Stat(label: 'Money Received', value: moneyReceived, color: AppColors.success)),
              const SizedBox(width: AppSizes.md),
              // Holds the two-column grid so "Money Received" stays in its
              // column rather than stretching across the card.
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
