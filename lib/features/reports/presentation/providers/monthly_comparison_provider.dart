import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/charts/domain/bar_chart_data.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// Income vs Expense per calendar month across the last [monthCount]
/// months (including the current one) — buckets
/// [calculableTransactionsProvider] by `Transaction.dateTime`'s own month,
/// the same real-date bucketing `CashFlowChart` uses for its weekly bars,
/// just at month granularity. No new totals: each month's income/expense
/// is the same `fold` every other Reports figure already does.
final monthlyComparisonProvider = Provider.family<AppBarChartData, int>((ref, monthCount) {
  final transactions = ref.watch(calculableTransactionsProvider);
  final now = DateTime.now();

  final months = <DateTime>[
    for (var i = monthCount - 1; i >= 0; i--) DateTime(now.year, now.month - i, 1),
  ];

  double totalFor(DateTime month, TransactionType type) {
    return transactions
        .where((t) =>
            t.type == type &&
            t.dateTime.year == month.year &&
            t.dateTime.month == month.month)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  return AppBarChartData.monthlyComparison(
    monthLabels: [for (final m in months) DateFormat('MMM').format(m)],
    seriesByName: {
      'Income': [for (final m in months) totalFor(m, TransactionType.income)],
      'Expense': [for (final m in months) totalFor(m, TransactionType.expense)],
    },
  );
});
