import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../shared/widgets/states/section_header.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../../transactions/presentation/widgets/transaction_tile.dart';
import '../../domain/reports_period.dart';
import '../widgets/category_spending_header.dart';
import '../widgets/category_spending_trend_chart.dart';
import '../widgets/category_summary_block.dart';
import '../widgets/reports_period_chips.dart';

/// Drill-down into a single category's spending over a period — total,
/// share of overall expenses, a daily trend chart, its transactions, and a
/// total/average/peak-day summary. Mirrors the Figma "Spending by Category"
/// screen.
class CategorySpendingDetailScreen extends ConsumerStatefulWidget {
  const CategorySpendingDetailScreen({super.key, required this.categoryId, this.initialPeriod});

  final String categoryId;
  final ReportsPeriod? initialPeriod;

  @override
  ConsumerState<CategorySpendingDetailScreen> createState() => _CategorySpendingDetailScreenState();
}

class _CategorySpendingDetailScreenState extends ConsumerState<CategorySpendingDetailScreen> {
  late ReportsPeriod _period = widget.initialPeriod ?? ReportsPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final category = categories.where((c) => c.id == widget.categoryId).firstOrNull;
    final allTransactions = ref.watch(calculableTransactionsProvider);
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final accountsById = {for (final a in accounts) a.id: a};

    if (category == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Spending by Category')),
        body: const EmptyState(
          icon: Icons.category_outlined,
          title: 'Category not found',
          subtitle: 'This category may have been deleted.',
        ),
      );
    }

    final now = DateTime.now();
    final range = _period.rangeFor(now);

    // Only month-granular periods honor Accounting Month (see
    // `ReportsPeriodX.isMonthGranular`) — everything else uses the real date.
    DateTime dateFor(Transaction t) => _period.isMonthGranular ? t.effectiveMonth : t.dateTime;
    // Transfers between the user's own accounts aren't real spending —
    // excluded so a transfer's source leg doesn't inflate category totals.
    final periodExpenses = allTransactions
        .where((t) => t.type == TransactionType.expense && range.contains(dateFor(t)) && !t.isTransfer)
        .toList();
    final categoryTransactions = periodExpenses.where((t) => t.categoryId == category.id).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final totalAllCategories = periodExpenses.fold(0.0, (sum, t) => sum + t.amount);
    final categoryTotal = categoryTransactions.fold(0.0, (sum, t) => sum + t.amount);
    final percentOfTotal = totalAllCategories == 0 ? 0.0 : categoryTotal / totalAllCategories;

    final daysInRange = range.end.dateOnly.difference(range.start.dateOnly).inDays + 1;
    final averagePerDay = daysInRange == 0 ? 0.0 : categoryTotal / daysInRange;

    DateTime? highestDay;
    var highestAmount = 0.0;
    final totalsByDay = <DateTime, double>{};
    for (final t in categoryTransactions) {
      final day = t.dateTime.dateOnly;
      totalsByDay.update(day, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    totalsByDay.forEach((day, amount) {
      if (amount > highestAmount) {
        highestAmount = amount;
        highestDay = day;
      }
    });

    final color = Color(category.colorValue);

    return Scaffold(
      appBar: AppBar(title: const Text('Spending by Category')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: [
          CategorySpendingHeader(category: category, total: categoryTotal, percentOfTotal: percentOfTotal),
          const SizedBox(height: AppSizes.lg),
          ReportsPeriodChips(selected: _period, onChanged: (p) => setState(() => _period = p)),
          const SizedBox(height: AppSizes.lg),
          CategorySpendingTrendChart(
            periodStart: range.start,
            periodEnd: range.end,
            transactions: categoryTransactions,
            color: color,
          ),
          const SizedBox(height: AppSizes.lg),
          SectionHeader(title: 'Transactions (${categoryTransactions.length})'),
          if (categoryTransactions.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions',
              subtitle: 'Expenses in this category will show up here.',
            )
          else
            for (final transaction in categoryTransactions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: TransactionTile(
                  transaction: transaction,
                  category: category,
                  account: accountsById[transaction.accountId],
                  onTap: () => context.push('${AppRoutes.transactions}/${transaction.id}'),
                ),
              ),
          const SizedBox(height: AppSizes.lg),
          CategorySummaryBlock(
            total: categoryTotal,
            averagePerDay: averagePerDay,
            highestSpendingDay: highestDay,
            highestSpendingAmount: highestAmount,
          ),
        ],
      ),
    );
  }
}
