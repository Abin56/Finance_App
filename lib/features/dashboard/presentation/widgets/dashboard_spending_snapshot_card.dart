import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../transactions/presentation/screens/add_expense_screen.dart';
import 'dashboard_section_card.dart';

/// Today's and this month's Income/Expense/Net at a glance, in one shared
/// card shell — replaces the old back-to-back `TodaySummaryCard` and
/// `DashboardMonthlySummaryCards`, which showed the same icon-badge stat
/// grammar twice at two time windows. Values are computed upstream in
/// `dashboard_screen.dart` from the same [transactionsStreamProvider] every
/// other Dashboard card already watches — this widget only renders them.
class DashboardSpendingSnapshotCard extends StatelessWidget {
  const DashboardSpendingSnapshotCard({
    super.key,
    required this.todayIncome,
    required this.todayExpense,
    required this.monthIncome,
    required this.monthExpense,
    required this.hasAnyTransactions,
  });

  final double todayIncome;
  final double todayExpense;
  final double monthIncome;
  final double monthExpense;

  /// False only when the account has never recorded a transaction — shows an
  /// empty state instead of a wall of ₹0s. A quiet day/month with real
  /// transaction history elsewhere still shows ₹0 rows, which is a normal
  /// state, not "empty."
  final bool hasAnyTransactions;

  @override
  Widget build(BuildContext context) {
    if (!hasAnyTransactions) {
      return PlaceholderCard(
        icon: Icons.receipt_long_outlined,
        title: 'Spending Snapshot',
        message: 'Add an income or expense to see today\'s and this month\'s totals here.',
        radius: AppSizes.radiusCard,
        actionLabel: 'Add a transaction',
        onTap: () => AddExpenseScreen.show(context),
      );
    }

    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          _StatRow(income: todayIncome, expense: todayExpense, thirdStatLabel: 'Net'),
          const SizedBox(height: AppSizes.md),
          Divider(height: 1, color: context.colors.onSurface.withValues(alpha: 0.08)),
          const SizedBox(height: AppSizes.md),
          Text('This Month', style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.sm),
          _StatRow(income: monthIncome, expense: monthExpense, thirdStatLabel: 'Savings'),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.income, required this.expense, required this.thirdStatLabel});

  final double income;
  final double expense;

  /// 'Net' for the daily row (a single day has no "savings" semantics),
  /// 'Savings' for the monthly row — matches the distinction the two cards
  /// this widget replaces (`TodaySummaryCard`/`DashboardMonthlySummaryCards`)
  /// each used.
  final String thirdStatLabel;

  @override
  Widget build(BuildContext context) {
    final net = income - expense;
    return Row(
      // Prevents a wrapped label at a large system font from stretching one
      // column taller than its neighbours and pulling their text out of
      // line — see test/shared/metric_row_alignment_test.dart.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Stat(icon: Icons.arrow_downward_rounded, label: 'Income', value: income, color: AppColors.income)),
        const SizedBox(width: AppSizes.sm),
        Expanded(child: _Stat(icon: Icons.arrow_upward_rounded, label: 'Expense', value: expense, color: AppColors.expense)),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _Stat(
            icon: Icons.account_balance_wallet_rounded,
            label: thirdStatLabel,
            value: net,
            color: net >= 0 ? AppColors.income : AppColors.expense,
          ),
        ),
      ],
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
          CurrencyFormatter.instance.formatCompact(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
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
