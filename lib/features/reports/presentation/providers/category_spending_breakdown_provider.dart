import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/reports_period.dart';
import '../widgets/reports_category_list.dart';

/// The same period+category ranking `ReportsScreen` computes inline
/// (verbatim extraction of the totalsByCategory/sort/percentOfTotal steps),
/// promoted to a provider so both the Reports screen and the Dashboard's
/// `spendingCategories` widget read one ranked list instead of each
/// re-deriving it. [period] decides which of a transaction's dates
/// (`ReportsPeriodX.reportDateFor`) buckets it into [range], matching every
/// other Reports figure.
final categorySpendingBreakdownProvider =
    Provider.family<List<CategorySpendingEntry>, ({DateRange range, ReportsPeriod period})>((ref, args) {
  final transactions = ref.watch(calculableTransactionsProvider);
  final categories = ref.watch(categoriesStreamProvider).value ?? const [];
  final categoriesById = {for (final c in categories) c.id: c};

  final periodTransactions = transactions.where(
    (t) => args.range.contains(args.period.reportDateFor(t)) && !t.isTransfer,
  );

  final expenses = periodTransactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (total, t) => total + t.amount);

  final totalsByCategory = <String, double>{};
  for (final t in periodTransactions.where((t) => t.type == TransactionType.expense)) {
    totalsByCategory.update(t.categoryId, (v) => v + t.amount, ifAbsent: () => t.amount);
  }

  final ranked = totalsByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final entry in ranked)
      if (categoriesById[entry.key] != null)
        CategorySpendingEntry(
          category: categoriesById[entry.key]!,
          amount: entry.value,
          percentOfTotal: expenses == 0 ? 0 : entry.value / expenses,
        ),
  ];
});
