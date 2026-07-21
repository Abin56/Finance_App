import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/account_stats.dart';

/// One account's [AccountStats] — the Account Details screen's stats
/// section watches this instead of re-deriving totals from the raw
/// transaction stream itself.
///
/// Only Income/Expense/Transfers In/Transfers Out are populated for now:
/// they're computable directly from [Transaction.type]/[Transaction.isTransfer],
/// the same fields every other balance/total aggregation in the app already
/// trusts. Credit Card Payments, Bills Paid, Loan/EMI Payments, and Split
/// Expense Payments are deliberately not inferred by matching category
/// names or descriptions — that would be a heuristic, not a reuse of
/// existing business logic. Add them here once `StatementPaymentRepository`
/// / `BillRepository` / the payment-schedule engine expose a reliable
/// account-scoped summary of their own; the UI renders whatever fields
/// [AccountStats] carries, so no screen change is needed when that lands.
final accountStatsProvider = Provider.autoDispose.family<AccountStats, String>((ref, accountId) {
  final transactions = ref.watch(calculableTransactionsProvider).where((t) => t.accountId == accountId);

  var income = 0.0;
  var expense = 0.0;
  var transfersIn = 0.0;
  var transfersOut = 0.0;
  var currentMonthExpense = 0.0;
  final now = DateTime.now();

  for (final t in transactions) {
    if (t.isTransfer) {
      if (t.type == TransactionType.income) {
        transfersIn += t.amount;
      } else {
        transfersOut += t.amount;
      }
      continue;
    }
    if (t.type == TransactionType.income) {
      income += t.amount;
    } else {
      expense += t.amount;
      if (t.dateTime.isSameMonth(now)) currentMonthExpense += t.amount;
    }
  }

  return AccountStats(
    income: income,
    expense: expense,
    transfersIn: transfersIn,
    transfersOut: transfersOut,
    currentMonthExpense: currentMonthExpense,
  );
});
