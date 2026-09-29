import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../categories/presentation/providers/category_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../transactions/domain/transaction.dart';
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
///
/// Personal spending counts only MY share of an expense: one paid for someone
/// else (split, or fully assigned to a person) is a People receivable, not my
/// consumption. A transaction with no linked [Expense] counts in full. Mirrors
/// Web `use-dashboard-data.ts` (`personalAmount`).
final categorySpendingBreakdownProvider =
    Provider.family<
      List<CategorySpendingEntry>,
      ({DateRange range, ReportsPeriod period})
    >((ref, args) {
      final transactions = ref.watch(calculableTransactionsProvider);
      final categories = ref.watch(categoriesStreamProvider).value ?? const [];
      final categoriesById = {for (final c in categories) c.id: c};
      final expenseByTransactionId = {
        for (final e in ref.watch(expensesStreamProvider).value ?? const [])
          if (e.deletedAt == null) e.transactionId: e,
      };
      double personalAmount(Transaction t) =>
          expenseByTransactionId[t.id]?.myShare ?? t.amount;

      final periodTransactions = transactions.where(
        (t) => args.range.contains(args.period.reportDateFor(t)),
      );

      final expenses = periodTransactions
          .where((t) => t.type == TransactionType.expense)
          .fold(0.0, (total, t) => total + personalAmount(t));

      final totalsByCategory = <String, double>{};
      for (final t in periodTransactions.where(
        (t) => t.type == TransactionType.expense,
      )) {
        final amount = personalAmount(t);
        if (amount == 0) continue; // entirely someone else's — not my spending
        totalsByCategory.update(
          t.categoryId,
          (v) => v + amount,
          ifAbsent: () => amount,
        );
      }

      final ranked = totalsByCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
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
