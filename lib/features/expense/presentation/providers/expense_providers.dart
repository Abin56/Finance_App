import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../data/expense_repository.dart';
import '../../domain/expense.dart';
import '../../domain/expense_participant.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final uid = ref.watch(currentUserIdProvider);
  final collection = firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.expenses)
      .withConverter<Expense>(
        fromFirestore: Expense.fromFirestore,
        toFirestore: (expense, _) => expense.toFirestore(),
      );
  return ExpenseRepository(
    collection,
    ref.watch(transactionRepositoryProvider),
    ref.watch(paymentScheduleRepositoryProvider),
    ref.watch(personRepositoryProvider),
    (scheduleId) => ref.watch(installmentRepositoryProvider(scheduleId)),
    (personId) => ref.watch(ledgerRepositoryProvider(personId)),
  );
});

final expensesStreamProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchAll();
});

final expensesTrashStreamProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchTrash();
});

/// Split expenses (participants non-empty) with at least one unsettled
/// participant — the dashboard's "pending splits" stat.
final pendingSplitExpensesProvider = Provider<List<Expense>>((ref) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  return expenses.where((e) {
    if (!e.isSplit || e.scheduleId == null) return false;
    final installments = ref.watch(installmentsStreamProvider(e.scheduleId!)).value ?? const [];
    return installments.any((i) => i.remainingAmount > 0);
  }).toList();
});

/// Sum of remaining (unsettled) amounts across every split expense's
/// participant installments.
final totalPendingSplitAmountProvider = Provider<double>((ref) {
  final expenses = ref.watch(pendingSplitExpensesProvider);
  return expenses.fold(0.0, (sum, e) => sum + ref.watch(remainingAmountProvider(e.scheduleId!)));
});

/// The split [Expense] linked to a given [Transaction.id], if any — the
/// reverse of [Expense.transactionId], for a Transaction Details screen that
/// needs to show participants/shares/status when a plain transaction turns
/// out to be a split expense's account-balance effect.
final expenseForTransactionProvider = Provider.family<Expense?, String>((ref, transactionId) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  return expenses.where((e) => e.transactionId == transactionId).firstOrNull;
});

/// One unsettled participant, paired with its owning [Expense] and tracking
/// [Installment] — the shape `MoneyReceivedSheet`'s split-expense-settlement
/// purpose (and any other "settle one participant" UI) needs, since a
/// participant's own remaining amount can differ from the whole expense's.
typedef PendingSplitParticipant = ({Expense expense, ExpenseParticipant participant, Installment installment});

/// Every unsettled participant across every split expense — one entry per
/// participant whose tracking installment still has a remaining amount,
/// regardless of whether they're linked to a tracked [Person].
final pendingSplitParticipantsProvider = Provider<List<PendingSplitParticipant>>((ref) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  final result = <PendingSplitParticipant>[];
  for (final expense in expenses) {
    if (!expense.isSplit || expense.scheduleId == null) continue;
    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final installmentsById = {for (final i in installments) i.id: i};
    for (final participant in expense.participants) {
      final installment = installmentsById[participant.installmentId];
      if (installment == null || installment.remainingAmount <= 0) continue;
      result.add((expense: expense, participant: participant, installment: installment));
    }
  }
  return result;
});

/// Maps every non-deleted expense [Transaction.id] to how much of it was
/// actually mine — the full amount for a plain (non-split) expense
/// transaction, or `Expense.myShare` when a split/assigned [Expense] is
/// linked to it. The single join point every "My Spending" provider and
/// Reports figure reduces over, so none of them re-derive the
/// Expense-vs-plain-transaction branching independently.
final myExpensePortionsProvider = Provider<Map<String, double>>((ref) {
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  final expenseByTransactionId = {
    for (final e in ref.watch(expensesStreamProvider).value ?? const []) e.transactionId: e,
  };
  return {
    for (final t in transactions)
      if (t.type == TransactionType.expense && !t.isDeleted) t.id: expenseByTransactionId[t.id]?.myShare ?? t.amount,
  };
});

/// Expense transactions paired with "how much of it was mine" — the shared
/// list every date-filtered My Spending/Reports figure below reduces over.
final _myExpenseTransactionsProvider = Provider<List<(Transaction, double)>>((ref) {
  final transactions = ref.watch(calculableTransactionsProvider);
  final portions = ref.watch(myExpensePortionsProvider);
  return [
    for (final t in transactions)
      if (t.type == TransactionType.expense && !t.isDeleted) (t, portions[t.id] ?? t.amount),
  ];
});

double _sumMyShareWhere(List<(Transaction, double)> entries, bool Function(Transaction) test) =>
    entries.where((e) => test(e.$1)).fold(0.0, (sum, e) => sum + e.$2);

/// Sum of "My Share" across every expense transaction, all-time.
final myTotalExpenseProvider = Provider<double>((ref) {
  final entries = ref.watch(_myExpenseTransactionsProvider);
  return entries.fold(0.0, (sum, e) => sum + e.$2);
});

/// Sum of "My Share" for expense transactions dated today.
final myTodayExpenseProvider = Provider<double>((ref) {
  final entries = ref.watch(_myExpenseTransactionsProvider);
  return _sumMyShareWhere(entries, (t) => t.dateTime.isToday);
});

/// Sum of "My Share" for expense transactions in the current calendar week
/// (Monday-start, matching `DateTimeX.startOfWeek`/`.endOfWeek`).
final myThisWeekExpenseProvider = Provider<double>((ref) {
  final entries = ref.watch(_myExpenseTransactionsProvider);
  final now = DateTime.now();
  return _sumMyShareWhere(entries, (t) => t.dateTime.isSameWeek(now));
});

/// Sum of "My Share" for expense transactions in the current calendar month.
final myThisMonthExpenseProvider = Provider<double>((ref) {
  final entries = ref.watch(_myExpenseTransactionsProvider);
  final now = DateTime.now();
  return _sumMyShareWhere(entries, (t) => t.effectiveMonth.isSameMonth(now));
});

/// Sum of "My Share" for expense transactions in the current calendar year.
final myThisYearExpenseProvider = Provider<double>((ref) {
  final entries = ref.watch(_myExpenseTransactionsProvider);
  final now = DateTime.now();
  return _sumMyShareWhere(entries, (t) => t.dateTime.year == now.year);
});

/// This month's "My Share" total divided by the number of days elapsed so
/// far this month (period-relative, not an all-time average).
final myAverageDailyExpenseProvider = Provider<double>((ref) {
  final total = ref.watch(myThisMonthExpenseProvider);
  final daysElapsed = DateTime.now().day;
  return daysElapsed <= 0 ? 0 : total / daysElapsed;
});

/// This year's "My Share" total divided by the number of calendar months
/// elapsed so far this year (period-relative, not an all-time average).
final myAverageMonthlyExpenseProvider = Provider<double>((ref) {
  final total = ref.watch(myThisYearExpenseProvider);
  final monthsElapsed = DateTime.now().month;
  return monthsElapsed <= 0 ? 0 : total / monthsElapsed;
});

/// Reports' period-scoped breakdown of "My Share": [personal] is my share of
/// expenses with no other participants at all, [split] is my share of
/// expenses I shared with others, [total] is the two combined — the same
/// number [myTotalExpenseProvider] would give for an all-time range.
typedef MyExpenseBreakdown = ({double personal, double split, double total});

/// My Share breakdown for [transactions] — the caller (Reports) is
/// responsible for having already filtered that list to the transactions
/// that belong in the period (via `calculableTransactionsProvider` +
/// `ReportsPeriod.reportDateFor`, the same filter every other Reports
/// figure uses), so this provider only ever does the Expense-join/My-Share
/// math, never its own independent date/exclusion filtering — avoids the
/// two ever silently disagreeing about which transactions are "in period".
final myExpenseBreakdownForTransactionsProvider = Provider.family<MyExpenseBreakdown, List<Transaction>>(
  (ref, transactions) {
    final expenseByTransactionId = {
      for (final e in ref.watch(expensesStreamProvider).value ?? const []) e.transactionId: e,
    };

    var personal = 0.0;
    var split = 0.0;
    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      final expense = expenseByTransactionId[t.id];
      if (expense != null && expense.isSplit) {
        split += expense.myShare;
      } else {
        personal += expense?.myShare ?? t.amount;
      }
    }
    return (personal: personal, split: split, total: personal + split);
  },
);

/// Sum of [InstallmentPayment.amount] collected from split-expense
/// participants whose owning [Expense] is dated within [start]..[end] —
/// Reports' "Money Received" figure, the one Task 7 number with no existing
/// analog (every other split-expense total reads cached `Installment`
/// fields rather than individual payments).
final moneyReceivedForRangeProvider = Provider.family<double, ({DateTime start, DateTime end})>((ref, range) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  var total = 0.0;
  for (final expense in expenses) {
    if (!expense.isSplit || expense.scheduleId == null) continue;
    if (expense.date.isBefore(range.start) || expense.date.isAfter(range.end)) continue;
    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    total += installments.fold(0.0, (sum, i) => sum + i.amountPaid);
  }
  return total;
});
