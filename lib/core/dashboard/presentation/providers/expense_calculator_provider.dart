import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/bills/presentation/providers/bill_occurrence_providers.dart';
import '../../../../features/bills/presentation/providers/bill_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../../../features/transactions/domain/transaction.dart';
import '../../../../features/transactions/domain/transaction_type.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../../payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../services/fiscal_year_controller.dart';
import '../../domain/date_range_strategy.dart';
import '../../domain/financial_view_module.dart';
import '../../domain/financial_view_result.dart';
import '../../domain/widget_configuration.dart';

/// Resolves one [WidgetConfiguration] (must be a `financialView` widget) into
/// its [FinancialViewResult] for "now". Every module strictly composes
/// existing repositories/providers — see the per-module helpers below — so
/// this never re-derives a total another feature already owns, and every
/// figure traces back to real repository data rather than a guessed
/// category match (no widget here invents a number).
///
/// Cached by Riverpod per [WidgetConfiguration] identity (`.autoDispose`
/// would drop the cache the moment a widget scrolls offscreen, which is
/// wasteful for a dashboard the user scrolls up and down constantly, so this
/// intentionally stays a plain family).
final financialViewResultProvider = Provider.family<FinancialViewResult, WidgetConfiguration>((ref, config) {
  final now = DateTime.now();
  final fiscalYearStartMonth = ref.watch(fiscalYearStartMonthProvider);
  final range = config.dateStrategy.resolve(now, fiscalYearStartMonth: fiscalYearStartMonth);

  final module = config.financialViewModule;
  final amount = _amountFor(ref, module, config.dateStrategy, range);
  final breakdown = _breakdownFor(ref, module, config.dateStrategy, range);

  final previousRange = _previousRangeFor(config.dateStrategy, range);
  final previousAmount =
      previousRange == null ? null : _amountFor(ref, module, config.dateStrategy, previousRange);

  return FinancialViewResult(
    module: module,
    range: range,
    amount: amount,
    previousAmount: previousAmount,
    breakdown: breakdown,
  );
});

/// The equal-length window immediately preceding [range], used for the "vs
/// last cycle" comparison — null for [CustomDateRange], which has no natural
/// "previous" window since it's an arbitrary one-off pick.
DateRange? _previousRangeFor(DateRangeStrategy strategy, DateRange range) {
  if (strategy is CustomDateRange) return null;
  final length = range.end.difference(range.start);
  return DateRange(range.start.subtract(length), range.start.subtract(const Duration(seconds: 1)));
}

double _amountFor(Ref ref, FinancialViewModule module, DateRangeStrategy strategy, DateRange range) {
  switch (module) {
    case FinancialViewModule.myExpenses:
      return _myExpenses(ref, strategy, range);
    case FinancialViewModule.sharedExpenses:
      return _sharedExpenses(ref, strategy, range);
    case FinancialViewModule.combinedExpenses:
      return _myExpenses(ref, strategy, range) +
          _sharedExpenses(ref, strategy, range) +
          _billsPaid(ref, range) +
          _emiPaid(ref, range) +
          _loanPaid(ref, range) +
          _creditCardPaid(ref, range);
    case FinancialViewModule.income:
      return _income(ref, strategy, range);
    case FinancialViewModule.netCashFlow:
      final moneyIn = _income(ref, strategy, range);
      final moneyOut = _myExpenses(ref, strategy, range) +
          _sharedExpenses(ref, strategy, range) +
          _billsPaid(ref, range) +
          _emiPaid(ref, range) +
          _loanPaid(ref, range) +
          _creditCardPaid(ref, range);
      return moneyIn - moneyOut;
  }
}

Map<String, double> _breakdownFor(Ref ref, FinancialViewModule module, DateRangeStrategy strategy, DateRange range) {
  if (module != FinancialViewModule.combinedExpenses && module != FinancialViewModule.netCashFlow) {
    return const {};
  }
  return {
    'My Expenses': _myExpenses(ref, strategy, range),
    'Shared Expenses': _sharedExpenses(ref, strategy, range),
    'Bills': _billsPaid(ref, range),
    'EMIs': _emiPaid(ref, range),
    'Loans': _loanPaid(ref, range),
    'Credit Card Payments': _creditCardPaid(ref, range),
  }..removeWhere((_, value) => value == 0);
}

/// The single date [transaction] must be bucketed by for [strategy] — mirrors
/// [ReportsPeriodX.reportDateFor]: [Transaction.effectiveMonth] (Accounting
/// Month) only when [strategy] resolves to a whole calendar month
/// ([ReportsPeriodStrategy] wrapping `thisMonth`/`lastMonth`), else
/// [Transaction.dateTime]. A salary-cycle window (17th→17th) is day-granular,
/// not month-granular, so `accountingMonth` — which only ever encodes a
/// month, never a day — has no well-defined position inside it; bucketing a
/// salary-cycle range by `effectiveMonth` would compare against the 1st of
/// the transaction's month and silently drop transactions that plainly fall
/// inside the cycle.
DateTime _bucketDateFor(DateRangeStrategy strategy, Transaction transaction) {
  final isMonthGranular = switch (strategy) {
    ReportsPeriodStrategy(:final period) => period.isMonthGranular,
    _ => false,
  };
  return isMonthGranular ? transaction.effectiveMonth : transaction.dateTime;
}

/// Every expense-type transaction in [range] — the single filter both
/// [_myExpenses] and [_sharedExpenses] build on, so they can never disagree
/// about which transactions are "in range". Sources from
/// [calculableTransactionsProvider] (excludes `excludeFromCalculations`) and
/// buckets by [_bucketDateFor], exactly like every other Dashboard/Reports/
/// Budget/Cash-Flow total in the app.
List<Transaction> _expenseTransactionsInRange(Ref ref, DateRangeStrategy strategy, DateRange range) {
  final transactions = ref.watch(calculableTransactionsProvider);
  return transactions
      .where((t) => t.type == TransactionType.expense && range.contains(_bucketDateFor(strategy, t)))
      .toList();
}

/// The portion of every expense in [range] that was actually mine — the full
/// amount for a plain/assigned expense, or [Expense.myShare] for a split one.
/// Delegates the Transaction+Expense join to
/// [myExpenseBreakdownForTransactionsProvider], the same one Reports uses, so
/// this never re-derives its own exclusion/date filtering.
double _myExpenses(Ref ref, DateRangeStrategy strategy, DateRange range) {
  final transactions = _expenseTransactionsInRange(ref, strategy, range);
  return ref.watch(myExpenseBreakdownForTransactionsProvider(transactions)).total;
}

/// The portion of every split expense in [range] that other participants
/// owe — never money I actually spent. Delegates to
/// [othersShareForTransactionsProvider], the same join/filter contract as
/// [_myExpenses].
double _sharedExpenses(Ref ref, DateRangeStrategy strategy, DateRange range) {
  final transactions = _expenseTransactionsInRange(ref, strategy, range);
  return ref.watch(othersShareForTransactionsProvider(transactions));
}

/// Real income transactions in [range].
double _income(Ref ref, DateRangeStrategy strategy, DateRange range) {
  final transactions = ref.watch(calculableTransactionsProvider);
  return transactions
      .where((t) => t.type == TransactionType.income && range.contains(_bucketDateFor(strategy, t)))
      .fold(0.0, (sum, t) => sum + t.amount);
}

/// Bills paid whose due date falls in [range]. Bills have no per-payment
/// timestamp — only a cumulative `amountPaid` per occurrence against that
/// occurrence's own `dueDate` — so, as with every other "paid" figure in
/// this app (`cash_flow_providers.dart`), a payment is bucketed by its
/// occurrence's due date rather than when it was actually paid. Mirrors
/// [_emiPaid]/[_loanPaid]/[_creditCardPaid]'s per-parent-then-per-child
/// fan-out exactly, one level added for Bills' template/occurrence split.
double _billsPaid(Ref ref, DateRange range) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  var paid = 0.0;
  for (final bill in bills) {
    final occurrences = ref.watch(billOccurrencesStreamProvider(bill.id)).value ?? const [];
    for (final occurrence in occurrences) {
      if (range.contains(occurrence.dueDate)) paid += occurrence.amountPaid;
    }
  }
  return paid;
}

double _emiPaid(Ref ref, DateRange range) {
  final emis = ref.watch(activeEmisProvider);
  var paid = 0.0;
  for (final emi in emis) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (range.contains(i.dueDate)) paid += i.amountPaid;
    }
  }
  return paid;
}

double _loanPaid(Ref ref, DateRange range) {
  final loans = ref.watch(activeLoansProvider);
  var paid = 0.0;
  for (final loan in loans) {
    final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (range.contains(i.dueDate)) paid += i.amountPaid;
    }
  }
  return paid;
}

double _creditCardPaid(Ref ref, DateRange range) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  var paid = 0.0;
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    for (final s in statements) {
      if (range.contains(s.dueDate)) paid += s.amountPaid;
    }
  }
  return paid;
}
