import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/bills/presentation/providers/bill_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../features/reports/domain/reports_period.dart';
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
  final amount = _amountFor(ref, module, range);
  final breakdown = _breakdownFor(ref, module, range);

  final previousRange = _previousRangeFor(config.dateStrategy, range);
  final previousAmount = previousRange == null ? null : _amountFor(ref, module, previousRange);

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

double _amountFor(Ref ref, FinancialViewModule module, DateRange range) {
  switch (module) {
    case FinancialViewModule.myExpenses:
      return _myExpenses(ref, range);
    case FinancialViewModule.sharedExpenses:
      return _sharedExpenses(ref, range);
    case FinancialViewModule.combinedExpenses:
      return _myExpenses(ref, range) +
          _sharedExpenses(ref, range) +
          _billsPaid(ref, range) +
          _emiPaid(ref, range) +
          _loanPaid(ref, range) +
          _creditCardPaid(ref, range);
    case FinancialViewModule.income:
      return _income(ref, range);
    case FinancialViewModule.transfers:
      return _transfers(ref, range);
    case FinancialViewModule.netCashFlow:
      final moneyIn = _income(ref, range);
      final moneyOut = _myExpenses(ref, range) +
          _sharedExpenses(ref, range) +
          _billsPaid(ref, range) +
          _emiPaid(ref, range) +
          _loanPaid(ref, range) +
          _creditCardPaid(ref, range);
      return moneyIn - moneyOut;
  }
}

Map<String, double> _breakdownFor(Ref ref, FinancialViewModule module, DateRange range) {
  if (module != FinancialViewModule.combinedExpenses && module != FinancialViewModule.netCashFlow) {
    return const {};
  }
  return {
    'My Expenses': _myExpenses(ref, range),
    'Shared Expenses': _sharedExpenses(ref, range),
    'Bills': _billsPaid(ref, range),
    'EMIs': _emiPaid(ref, range),
    'Loans': _loanPaid(ref, range),
    'Credit Card Payments': _creditCardPaid(ref, range),
  }..removeWhere((_, value) => value == 0);
}

/// The portion of every [Expense] in [range] that was actually mine
/// ([Expense.myShare]) — the full amount for a plain/assigned expense, or my
/// own participant share for a split one. Filtered by [Expense.date], the
/// expense's own date (expenses have no accounting-month override the way
/// [Transaction] does).
double _myExpenses(Ref ref, DateRange range) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  return expenses.where((e) => range.contains(e.date)).fold(0.0, (sum, e) => sum + e.myShare);
}

/// The portion of every split [Expense] in [range] that other participants
/// owe — [Expense.totalAmount] minus my own share, so a split expense's
/// "shared" total never includes the part I already paid for myself.
double _sharedExpenses(Ref ref, DateRange range) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  return expenses.where((e) => e.isSplit && range.contains(e.date)).fold(
        0.0,
        (sum, e) => sum + (e.totalAmount - e.myShare),
      );
}

/// Real income transactions in [range] — transfers excluded since a
/// transfer between the user's own accounts isn't real income, matching
/// every other aggregation in the app ([Transaction.isTransfer]).
double _income(Ref ref, DateRange range) {
  final transactions = ref.watch(calculableTransactionsProvider);
  return transactions
      .where((t) => t.type == TransactionType.income && !t.isTransfer && range.contains(t.effectiveMonth))
      .fold(0.0, (sum, t) => sum + t.amount);
}

/// Sum of one leg of every transfer pair whose date falls in [range] — each
/// transfer posts two transactions sharing a `transferId`, so this counts
/// only the expense (outgoing) leg to avoid double-counting the same
/// transfer twice.
double _transfers(Ref ref, DateRange range) {
  final transactions = ref.watch(calculableTransactionsProvider);
  return transactions
      .where((t) => t.isTransfer && t.type == TransactionType.expense && range.contains(t.effectiveMonth))
      .fold(0.0, (sum, t) => sum + t.amount);
}

/// Bills paid whose due date falls in [range]. Bills have no per-payment
/// timestamp — only a cumulative `amountPaid` against one `dueDate` — so, as
/// with every other "paid" figure in this app (`cash_flow_providers.dart`),
/// a payment is bucketed by its bill's due date rather than when it was
/// actually paid.
double _billsPaid(Ref ref, DateRange range) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  return bills.where((b) => range.contains(b.dueDate)).fold(0.0, (sum, b) => sum + b.amountPaid);
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
