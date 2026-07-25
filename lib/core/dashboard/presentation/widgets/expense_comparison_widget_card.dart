import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../../../features/transactions/domain/transaction_type.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../services/fiscal_year_controller.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/widget_configuration.dart';
import 'dashboard_widget_shell.dart';

/// Renders [DashboardWidgetType.expenseComparison] — my share of this
/// widget's date range's expenses against what other split-expense
/// participants owe, via [myExpenseBreakdownForTransactionsProvider] and
/// [othersShareForTransactionsProvider] — the exact same two providers
/// [financialViewResultProvider]'s combinedExpenses module already sums
/// into its "My Expenses"/"Shared Expenses" breakdown rows, just given
/// their own dedicated, always-visible card rather than living inside an
/// optional Financial View instance.
class ExpenseComparisonWidgetCard extends ConsumerWidget {
  const ExpenseComparisonWidgetCard({super.key, required this.config});

  final WidgetConfiguration config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final fiscalYearStartMonth = ref.watch(fiscalYearStartMonthProvider);
    final range = config.dateStrategy.resolve(now, fiscalYearStartMonth: fiscalYearStartMonth);
    final isMonthGranular = switch (config.dateStrategy) {
      ReportsPeriodStrategy(:final period) => period.isMonthGranular,
      _ => false,
    };

    final allTransactions = ref.watch(calculableTransactionsProvider);
    final transactions = allTransactions
        .where(
          (t) =>
              t.type == TransactionType.expense &&
              !t.isTransfer &&
              range.contains(isMonthGranular ? t.effectiveMonth : t.dateTime),
        )
        .toList();

    final myExpenses = ref.watch(myExpenseBreakdownForTransactionsProvider(transactions)).total;
    final othersShare = ref.watch(othersShareForTransactionsProvider(transactions));
    final total = myExpenses + othersShare;
    final myFraction = total <= 0 ? 0.5 : (myExpenses / total).clamp(0.0, 1.0);
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final textTheme = context.textTheme;
    final colors = context.colors;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(config.title, style: textTheme.labelLarge, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSizes.lg),
          if (total <= 0)
            Text(
              'No expenses in this period yet.',
              style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _ComparisonStat(
                    label: 'My Expenses',
                    amount: myExpenses,
                    color: AppColors.primary,
                    format: format,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: _ComparisonStat(
                    label: 'People\'s Share',
                    amount: othersShare,
                    color: AppColors.secondary,
                    format: format,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusPill),
              child: Row(
                children: [
                  Expanded(
                    flex: (myFraction * 1000).round().clamp(1, 999),
                    child: Container(height: 10, color: AppColors.primary),
                  ),
                  Expanded(
                    flex: (1000 - (myFraction * 1000).round()).clamp(1, 999),
                    child: Container(height: 10, color: AppColors.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(myFraction * 100).round()}% mine',
                  style: textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${(100 - myFraction * 100).round()}% others\'',
                  style: textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ComparisonStat extends StatelessWidget {
  const _ComparisonStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.format,
    this.alignEnd = false,
  });

  final String label;
  final double amount;
  final Color color;
  final NumberFormat format;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final crossAlign = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;
    final boxAlign = alignEnd ? Alignment.centerRight : Alignment.centerLeft;
    final dot = Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    final labelText = Flexible(
      child: Text(
        label,
        style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Column(
      crossAxisAlignment: crossAlign,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: alignEnd
              ? [labelText, const SizedBox(width: AppSizes.xs), dot]
              : [dot, const SizedBox(width: AppSizes.xs), labelText],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: boxAlign,
          child: Text(
            format.format(amount),
            style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
            textAlign: textAlign,
          ),
        ),
      ],
    );
  }
}
