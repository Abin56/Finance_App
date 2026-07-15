import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// Today's income/expense at a glance — a quick "how's today going" check
/// distinct from the month-level [DashboardMonthlySummaryCards], filtered
/// from the same [transactionsStreamProvider] every other Dashboard stat
/// already watches.
class TodaySummaryCard extends ConsumerWidget {
  const TodaySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
    // Transfers between the user's own accounts aren't real income/expense —
    // excluded here so a transfer's two legs don't inflate both totals.
    final today = transactions.where((t) => t.dateTime.isToday && !t.isDeleted && !t.isTransfer);

    final income = today
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);
    final expense = today
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (sum, t) => sum + t.amount);

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
      ),
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's Summary", style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _Stat(icon: Icons.arrow_downward_rounded, label: 'Income', value: income, color: AppColors.income),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _Stat(icon: Icons.arrow_upward_rounded, label: 'Expense', value: expense, color: AppColors.expense),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: _Stat(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Net',
                  value: income - expense,
                  color: income - expense >= 0 ? AppColors.income : AppColors.expense,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}
