import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../providers/person_expense_stats_provider.dart';

/// The Contact Ledger's reconciliation stat card (Figma frame 1) — a
/// two-column layout: `You will receive` (big, with a "To Receive" pill)
/// beside `Total Settled` and `Total Spent`, scoped to this person's
/// split/assigned **Expense** participations. `Total Spent = Total Settled +
/// You will receive` holds by construction — see [PersonExpenseStats.pending].
class PersonExpenseStatsCard extends StatelessWidget {
  const PersonExpenseStatsCard({super.key, required this.stats});

  final PersonExpenseStats stats;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You will receive',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.instance.format(stats.pending),
                  style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success),
                ),
                const SizedBox(height: AppSizes.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Text(
                    'To Receive',
                    style: context.textTheme.labelSmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _MiniStat(label: 'Total Settled', value: stats.totalSettled),
                const SizedBox(height: AppSizes.md),
                _MiniStat(label: 'Total Spent', value: stats.totalSpent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 2),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
