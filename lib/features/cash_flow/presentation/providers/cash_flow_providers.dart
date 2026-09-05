import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../shared/domain/payment_urgency.dart';
import '../../../bills/domain/bill_status.dart';
import '../../../bills/presentation/providers/bill_occurrence_providers.dart';
import '../../../bills/presentation/providers/bill_providers.dart';
import '../../../credit_cards/domain/credit_card_profile.dart';
import '../../../credit_cards/domain/credit_card_status.dart';
import '../../../credit_cards/domain/statement.dart';
import '../../../credit_cards/domain/statement_status.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../reports/domain/reports_period.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/cash_flow_period.dart';
import '../../domain/money_flow_line.dart';

/// Aggregation providers for the Dashboard's "Cash Flow Center" sections.
/// Every provider below strictly composes existing providers/model getters
/// — no new Firestore reads, no reimplemented remaining-amount or status
/// math. See `lib/features/*/domain/*.dart` for the underlying `.status`/
/// `.remainingAmount` computations this file only ever reads, never repeats.
///
/// Section 1's "due this month" breakdowns intentionally deviate from the
/// underlying repositories' `thisMonth()`/calendar-month semantics: they
/// merge this month's items with anything still unpaid from a prior cycle
/// (each module's own `*CycleViewProvider.previousCyclePending`, the same
/// shared `CycleEngine`-classified carry-forward set Credit Cards/EMI/
/// Loan/Bills/People already surface on their own screens — see
/// `cycle_engine.dart`), so "Payments Due This Month" reflects what the
/// user actually owes right now rather than contradicting Section 4's
/// timeline, which already surfaces carried-over items regardless of
/// month. `InstallmentRepository.thisMonth`/`Bill`/`Statement` themselves
/// are left untouched — every other screen that reads them keeps strict
/// calendar-month behavior.

/// A single row's due/paid/remaining figures for Section 1 ("Payments Due
/// This Month").
typedef DueCategoryBreakdown = ({double due, double paid, double remaining});

const _zeroBreakdown = (due: 0.0, paid: 0.0, remaining: 0.0);

DueCategoryBreakdown _combine(Iterable<DueCategoryBreakdown> rows) {
  final due = rows.fold(0.0, (sum, r) => sum + r.due);
  final paid = rows.fold(0.0, (sum, r) => sum + r.paid);
  return (due: due, paid: paid, remaining: due - paid);
}

/// Sum of this-month installment due/paid across every active EMI, plus any
/// still-unpaid installment carried forward from a prior cycle per the
/// shared `CycleEngine` (`emiCycleViewRecordProvider`).
final emiDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final now = DateTime.now();
  final emis = ref.watch(activeEmisProvider);
  var due = 0.0, paid = 0.0;
  for (final emi in emis) {
    final view = ref.watch(emiCycleViewRecordProvider(emi));
    final carriedOver = view.previousCyclePending;
    final thisMonth = view.current.where((i) => i.dueDate.isSameMonth(now));
    for (final i in {...carriedOver, ...thisMonth}) {
      due += i.amountDue;
      paid += i.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Sum of this-month installment due/paid across every active Loan, plus any
/// still-unpaid installment carried forward from a prior cycle per the
/// shared `CycleEngine` (`loanCycleViewRecordProvider`).
final loanDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final now = DateTime.now();
  final loans = ref.watch(activeLoansProvider);
  var due = 0.0, paid = 0.0;
  for (final loan in loans) {
    final view = ref.watch(loanCycleViewRecordProvider(loan));
    final carriedOver = view.previousCyclePending;
    final thisMonth = view.current.where((i) => i.dueDate.isSameMonth(now));
    for (final i in {...carriedOver, ...thisMonth}) {
      due += i.amountDue;
      paid += i.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Sum of this-month bill amount/paid, excluding skipped occurrences, plus
/// any still-unpaid occurrence carried forward from a prior cycle per the
/// shared `CycleEngine` (`billOccurrenceCycleViewProvider`). Fans out
/// per-bill, same as [emiDueThisMonthBreakdownProvider]/
/// [loanDueThisMonthBreakdownProvider] fan out per-owner.
final billsDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final now = DateTime.now();
  var due = 0.0, paid = 0.0;
  for (final bill in bills) {
    final view = ref.watch(billOccurrenceCycleViewProvider(bill.id));
    final carriedOver = view.previousCyclePending;
    final current = view.current;
    final thisMonth = current != null && current.dueDate.isSameMonth(now) ? [current] : const [];
    for (final o in {...carriedOver, ...thisMonth}) {
      if (o.status == BillStatus.skipped) continue;
      due += o.amount;
      paid += o.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Sum of this-month statement total/paid across every card, excluding
/// already-paid statements, plus any still-unpaid statement carried forward
/// from a prior cycle per the shared `CycleEngine`
/// (`statementCycleViewProvider`).
final creditCardDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final now = DateTime.now();
  var due = 0.0, paid = 0.0;
  for (final card in cards) {
    final view = ref.watch(statementCycleViewProvider(card.id));
    final carriedOver = view.previousCyclePending;
    final current = view.current;
    final thisMonth = current != null && current.dueDate.isSameMonth(now) ? [current] : const [];
    for (final s in {...carriedOver, ...thisMonth}) {
      if (s.status == StatementStatus.paid) continue;
      due += s.totalAmount;
      paid += s.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// No distinct "Other Scheduled Payments" data source exists today — kept
/// as an explicit provider (always zero) so the widget's row list is
/// stable and the row can simply be hidden when zero, per the Cash Flow
/// Center plan's clarified UX decision, rather than being omitted here.
final otherScheduledDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) => _zeroBreakdown);

/// Overall roll-up for Section 1's headline Total Due/Paid/Remaining.
final totalDueThisMonthProvider = Provider<DueCategoryBreakdown>((ref) {
  return _combine([
    ref.watch(creditCardDueThisMonthBreakdownProvider),
    ref.watch(emiDueThisMonthBreakdownProvider),
    ref.watch(loanDueThisMonthBreakdownProvider),
    ref.watch(billsDueThisMonthBreakdownProvider),
    ref.watch(otherScheduledDueThisMonthBreakdownProvider),
  ]);
});

/// A single row's amount/count for Section 2 ("Money To Receive").
typedef ReceivableCategoryBreakdown = ({double amount, int count});

const _zeroReceivable = (amount: 0.0, count: 0);

/// Split expenses still owed to me by *untracked* participants only —
/// participants linked to a [Person] already post a ledger entry counted
/// under [peoplePendingReceivableProvider], so they're excluded here to
/// avoid double-counting the same receivable in both rows.
final splitExpensesReceivableProvider = Provider<ReceivableCategoryBreakdown>((ref) {
  final pending = ref.watch(pendingSplitExpensesProvider).where(
        (e) => e.participants.any((p) => !p.isMe && p.personId == null),
      );
  final amount = ref.watch(untrackedPendingSplitAmountProvider);
  return (amount: amount, count: pending.length);
});

/// No distinct "Assigned Expenses" concept exists beyond a single-
/// participant split today — kept as an explicit zero provider, hidden by
/// the widget when zero.
final assignedExpensesReceivableProvider = Provider<ReceivableCategoryBreakdown>((ref) => _zeroReceivable);

/// Money owed to me by tracked people (People/Ledger feature).
final peoplePendingReceivableProvider = Provider<ReceivableCategoryBreakdown>((ref) {
  final creditors = ref.watch(creditorsProvider);
  return (amount: ref.watch(totalReceivableProvider), count: creditors.length);
});

/// Loans I've given to others, still outstanding (Lending feature) —
/// independent of the People ledger (Loan has no link to LedgerRepository),
/// so this never double-counts against [peoplePendingReceivableProvider].
final loanRecoveriesReceivableProvider = Provider<ReceivableCategoryBreakdown>((ref) {
  final loans = ref.watch(activeLoansProvider);
  return (amount: ref.watch(totalAmountToReceiveProvider), count: loans.length);
});

/// No "Other Receivables" data source exists today — hidden by the widget
/// when zero, same rationale as [assignedExpensesReceivableProvider].
final otherReceivablesProvider = Provider<ReceivableCategoryBreakdown>((ref) => _zeroReceivable);

/// Overall roll-up for Section 2's headline Total.
final totalMoneyToReceiveProvider = Provider<double>((ref) {
  return ref.watch(splitExpensesReceivableProvider).amount +
      ref.watch(assignedExpensesReceivableProvider).amount +
      ref.watch(peoplePendingReceivableProvider).amount +
      ref.watch(loanRecoveriesReceivableProvider).amount +
      ref.watch(otherReceivablesProvider).amount;
});

/// One card's statement summary for Section 3.
typedef CardStatementSummary = ({
  CreditCardProfile card,
  Statement? latestStatement,
  CreditCardStanding standing,
});

/// Every active card's current (or most recent) statement plus its running
/// standing — Section 3's data source.
final activeCardStatementSummariesProvider = Provider<List<CardStatementSummary>>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final result = <CardStatementSummary>[];
  for (final card in cards.where((c) => c.status.isActive)) {
    var latest = ref.watch(currentStatementCycleProvider(card.id));
    if (latest == null) {
      final statements = ref.watch(statementsWithLiveTotalsProvider(card.id));
      if (statements.isNotEmpty) {
        final sorted = [...statements]..sort((a, b) => b.dueDate.compareTo(a.dueDate));
        latest = sorted.first;
      }
    }
    result.add((
      card: card,
      latestStatement: latest,
      standing: ref.watch(creditCardStandingProvider(card.id)),
    ));
  }
  return result;
});

/// Which domain an [UpcomingPaymentItem] came from, for routing on tap.
enum UpcomingPaymentKind { emi, loan, bill, creditCard }

/// One merged row in Section 4's upcoming-payments timeline. [isCarriedOver]
/// mirrors the Dashboard's `UpcomingDueItem.isCarriedOver` — both are now
/// sourced from the same per-module `*CycleViewProvider`s, so a row flagged
/// here agrees with what that module's own screen shows as "Previous Cycle
/// Pending".
typedef UpcomingPaymentItem = ({
  UpcomingPaymentKind kind,
  String title,
  DateTime dueDate,
  double amountDue,
  double remaining,
  PaymentUrgency urgency,
  bool isCarriedOver,
  String routeId,
});

/// Every unpaid, non-skipped EMI/Loan installment, Bill, and Credit Card
/// statement, merged and sorted with overdue items always first (regardless
/// of date), then ascending due date — Section 4's data source. Carry-
/// forward status comes from each module's own `*CycleViewProvider`, the
/// same shared `CycleEngine`-classified set [emiDueThisMonthBreakdownProvider]
/// and friends above read — no independent cutoff logic of this provider's
/// own.
final upcomingPaymentsTimelineProvider = Provider<List<UpcomingPaymentItem>>((ref) {
  final items = <UpcomingPaymentItem>[];

  for (final emi in ref.watch(activeEmisProvider)) {
    final view = ref.watch(emiCycleViewRecordProvider(emi));
    final relevant = [...view.previousCyclePending, ...view.current];
    for (final i in relevant) {
      if (i.status == InstallmentStatus.paid || i.isSkipped) continue;
      final isCarriedOver = view.previousCyclePending.contains(i);
      items.add((
        kind: UpcomingPaymentKind.emi,
        title: emi.name,
        dueDate: i.dueDate,
        amountDue: i.amountDue,
        remaining: i.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromInstallmentStatus(i.status),
        isCarriedOver: isCarriedOver,
        routeId: emi.id,
      ));
    }
  }

  for (final loan in ref.watch(activeLoansProvider)) {
    final view = ref.watch(loanCycleViewRecordProvider(loan));
    final relevant = [...view.previousCyclePending, ...view.current];
    for (final i in relevant) {
      if (i.status == InstallmentStatus.paid || i.isSkipped) continue;
      final isCarriedOver = view.previousCyclePending.contains(i);
      items.add((
        kind: UpcomingPaymentKind.loan,
        title: loan.name ?? 'Loan',
        dueDate: i.dueDate,
        amountDue: i.amountDue,
        remaining: i.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromInstallmentStatus(i.status),
        isCarriedOver: isCarriedOver,
        routeId: loan.id,
      ));
    }
  }

  final bills = ref.watch(billsStreamProvider).value ?? const [];
  for (final bill in bills) {
    final view = ref.watch(billOccurrenceCycleViewProvider(bill.id));
    final relevant = [...view.previousCyclePending, if (view.current != null) view.current!];
    for (final o in relevant) {
      if (o.status == BillStatus.paid || o.status == BillStatus.skipped) continue;
      final isCarriedOver = view.previousCyclePending.contains(o);
      items.add((
        kind: UpcomingPaymentKind.bill,
        title: bill.name,
        dueDate: o.dueDate,
        amountDue: o.amount,
        remaining: o.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromBillStatus(o.status),
        isCarriedOver: isCarriedOver,
        routeId: bill.id,
      ));
    }
  }

  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  for (final card in cards) {
    final view = ref.watch(statementCycleViewProvider(card.id));
    final relevant = [...view.previousCyclePending, if (view.current != null) view.current!];
    for (final s in relevant) {
      if (s.status == StatementStatus.paid) continue;
      final isCarriedOver = view.previousCyclePending.contains(s);
      items.add((
        kind: UpcomingPaymentKind.creditCard,
        title: card.lastFourDigits != null ? 'Card •••• ${card.lastFourDigits}' : 'Credit Card',
        dueDate: s.dueDate,
        amountDue: s.totalAmount,
        remaining: s.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromStatementStatus(s.status),
        isCarriedOver: isCarriedOver,
        routeId: card.id,
      ));
    }
  }

  items.sort((a, b) {
    final aOverdue = a.urgency == PaymentUrgency.overdue;
    final bOverdue = b.urgency == PaymentUrgency.overdue;
    if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
    return a.dueDate.compareTo(b.dueDate);
  });
  return items;
});

/// Section 5's Money In/Out/Net figures.
typedef CashFlowSummary = ({double moneyIn, double moneyOut, double net});

/// The Dashboard's "this calendar month" cash flow — evaluates the exact
/// same [moneyInLinesForRangeFamilyProvider]/[moneyOutLinesForRangeFamilyProvider]
/// the Cash Flow screen uses, just with a fixed This-Month period instead of
/// the user-selected [cashFlowDateRangeProvider], rather than keeping a
/// second, independently-maintained calculation. Money In/Out here can
/// never silently diverge from the Cash Flow screen's own This-Month
/// figures, and no account type (bank, credit card, cash, wallet, ...) is
/// ever filtered by either — see [moneyOutLinesForRangeFamilyProvider]'s doc
/// comment for why a credit-card purchase is included on equal footing with
/// any other account's expense.
final cashFlowThisMonthProvider = Provider<CashFlowSummary>((ref) {
  final now = DateTime.now();
  const period = CashFlowPeriod.preset(CashFlowPreset.thisMonth);
  final range = period.rangeFor(now);
  final key = (period: period, range: range);
  final moneyIn = ref.watch(moneyInLinesForRangeFamilyProvider(key)).fold(0.0, (s, l) => s + l.amount);
  final moneyOut = ref.watch(moneyOutLinesForRangeFamilyProvider(key)).fold(0.0, (s, l) => s + l.amount);
  return (moneyIn: moneyIn, moneyOut: moneyOut, net: moneyIn - moneyOut);
});

// ---------------------------------------------------------------------------
// Date-range filter (Feature: Cash Flow date range)
// ---------------------------------------------------------------------------
//
// The Cash Flow screen's single selected date range, defaulting to the
// current calendar month. Only the sections built directly on
// `calculableTransactionsProvider` (Section 5 "Cash Flow Summary" and the
// "My Expenses" section below) can be meaningfully scoped to an arbitrary
// user-picked range — Sections 1/3/4 (Payments Due, Credit Card Statement
// Summary, Upcoming Payments) are built on each module's `CycleEngine`
// carry-forward classification (due-cycle/statement-cycle semantics, not an
// arbitrary window), so they deliberately keep showing "what's currently
// owed" regardless of this range rather than being forced into a filter
// that would misrepresent overdue/carried-over amounts. Section 2 (Money To
// Receive) is an outstanding-balance concept, not date-scoped either.
final cashFlowDateRangeProvider = StateProvider<CashFlowPeriod>((ref) {
  return const CashFlowPeriod.preset(CashFlowPreset.thisMonth);
});

/// [cashFlowDateRangeProvider]'s period resolved against "now" into a
/// concrete [DateRange] — the single value every range-scoped Cash Flow
/// provider below reads, so "This Month" rolls forward at a month boundary
/// without every consumer re-deriving `DateTime.now()` independently.
final resolvedCashFlowRangeProvider = Provider<DateRange>((ref) {
  final period = ref.watch(cashFlowDateRangeProvider);
  return period.rangeFor(DateTime.now());
});

/// A (period, range) pair — the argument every range-parameterized Money
/// In/Out line provider below takes, so the exact same calculation can be
/// evaluated for the Cash Flow screen's user-selected period AND the
/// Dashboard's fixed "this month" period without duplicating the logic
/// itself (see [moneyInLinesForRangeFamilyProvider]/
/// [moneyOutLinesForRangeFamilyProvider] and [cashFlowThisMonthProvider]).
typedef _PeriodRange = ({CashFlowPeriod period, DateRange range});

/// Every [MoneyFlowLine] that contributes to Money In for [key]'s range —
/// plain income transactions, plus split-expense settlements collected from
/// others (via each expense's own tracked installments). No account type
/// (bank, credit card, cash, wallet, ...) is ever filtered here or anywhere
/// downstream — [Transaction.accountId] only ever affects the line's
/// display `accountLabel`, never whether it's included.
///
/// Bucketing: plain transactions are matched against
/// [CashFlowPeriod.bucketDateFor] (so a whole-month preset still respects
/// `accountingMonth`, while a day-precision custom range reads the
/// transaction's real [Transaction.dateTime] instead of the month-truncated
/// `effectiveMonth` — the bug this replaces). Split-expense settlements are
/// bucketed by the linked transaction's own date, exactly matching
/// [moneyReceivedForRangeProvider]'s existing rule, so this is additive
/// with that provider rather than a second reimplementation of it.
final moneyInLinesForRangeFamilyProvider = Provider.family<List<MoneyFlowLine>, _PeriodRange>((ref, key) {
  final period = key.period;
  final range = key.range;
  final categoriesById = {for (final c in ref.watch(categoriesStreamProvider).value ?? const []) c.id: c};
  final accountsById = {for (final a in ref.watch(accountsStreamProvider).value ?? const []) a.id: a};

  final lines = <MoneyFlowLine>[];

  final transactions = ref.watch(calculableTransactionsProvider);
  for (final t in transactions) {
    if (t.isDeleted || t.type != TransactionType.income) continue;
    final bucketDate = period.bucketDateFor(t);
    if (bucketDate.isBefore(range.start) || bucketDate.isAfter(range.end)) continue;
    lines.add((
      kind: MoneyFlowKind.income,
      date: t.dateTime,
      title: t.description.isNotEmpty ? t.description : 'Income',
      amount: t.amount,
      categoryLabel: categoriesById[t.categoryId]?.name,
      accountLabel: accountsById[t.accountId]?.name,
    ));
  }

  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  final calculableById = {for (final t in transactions) t.id: t};
  for (final expense in expenses) {
    if (!expense.isSplit || expense.scheduleId == null) continue;
    final transaction = calculableById[expense.transactionId];
    if (transaction == null) continue;
    final bucketDate = period.bucketDateFor(transaction);
    if (bucketDate.isBefore(range.start) || bucketDate.isAfter(range.end)) continue;
    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final collected = installments.fold(0.0, (sum, i) => sum + i.amountPaid);
    if (collected <= 0) continue;
    lines.add((
      kind: MoneyFlowKind.moneyReceived,
      date: transaction.dateTime,
      title: 'Money received: ${expense.description}',
      amount: collected,
      categoryLabel: categoriesById[expense.categoryId]?.name,
      accountLabel: accountsById[expense.accountId]?.name,
    ));
  }

  lines.sort((a, b) => b.date.compareTo(a.date));
  return lines;
});

/// Every [MoneyFlowLine] that contributes to Money Out for [key]'s range —
/// EVERY qualifying expense transaction regardless of which [Account]/
/// [AccountType] it's posted against (bank, credit card, cash, wallet, or
/// any other type this app supports), plus EMI/Loan/Bill payments (which
/// never post their own [Transaction], see [cashFlowThisMonthProvider]'s
/// doc comment). A credit-card purchase is stored as an ordinary
/// [Transaction] on that card's [Account] — see `CreditCardProfile.accountId`
/// — so it is already included by the same unfiltered loop as any other
/// account's expense transaction; there is deliberately no `accountId`/
/// `AccountType`/"is this a credit card" branch anywhere in this provider.
/// Same single-source-of-truth contract as
/// [moneyInLinesForRangeFamilyProvider]: whichever total reads this (Cash
/// Flow screen or Dashboard) sums these exact lines, so the summary and the
/// Money Out detail screen can never drift apart, and "This Month" can
/// never see a different set of account types than "This Week"/a custom
/// range — the period only ever changes WHICH transactions fall inside
/// [key.range], never WHICH ACCOUNTS are eligible.
///
/// EMI/Loan/Bill lines are bucketed by the installment/occurrence's own due
/// date — same rule [emiPaidThisMonthProvider] and friends already use for
/// "this month" (a payment counts toward whichever cycle it was due in, not
/// necessarily the day it was actually paid) — generalized here to an
/// arbitrary range instead of always the current calendar month. A
/// credit-card STATEMENT payment (paying off the card's bill) is distinct
/// from a credit-card PURCHASE: the purchase already counted once as an
/// ordinary expense [Transaction] above, and paying the statement later
/// moves money between the card account and the paying account without
/// posting a second expense transaction — see `CreditCardStatementSummaryCard`'s
/// own section, which tracks statement payment status separately and is
/// never summed into this provider, so a purchase is never double-counted
/// against its own later bill payment.
final moneyOutLinesForRangeFamilyProvider = Provider.family<List<MoneyFlowLine>, _PeriodRange>((ref, key) {
  final period = key.period;
  final range = key.range;
  final categoriesById = {for (final c in ref.watch(categoriesStreamProvider).value ?? const []) c.id: c};
  final accountsById = {for (final a in ref.watch(accountsStreamProvider).value ?? const []) a.id: a};

  final lines = <MoneyFlowLine>[];

  final transactions = ref.watch(calculableTransactionsProvider);
  for (final t in transactions) {
    if (t.isDeleted || t.type != TransactionType.expense) continue;
    final bucketDate = period.bucketDateFor(t);
    if (bucketDate.isBefore(range.start) || bucketDate.isAfter(range.end)) continue;
    lines.add((
      kind: MoneyFlowKind.expense,
      date: t.dateTime,
      title: t.description.isNotEmpty ? t.description : 'Expense',
      amount: t.amount,
      categoryLabel: categoriesById[t.categoryId]?.name,
      accountLabel: accountsById[t.accountId]?.name,
    ));
  }

  for (final emi in ref.watch(activeEmisProvider)) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (i.dueDate.isBefore(range.start) || i.dueDate.isAfter(range.end)) continue;
      if (i.amountPaid <= 0) continue;
      lines.add((
        kind: MoneyFlowKind.emi,
        date: i.dueDate,
        title: emi.name,
        amount: i.amountPaid,
        categoryLabel: 'EMI',
        accountLabel: null,
      ));
    }
  }

  for (final loan in ref.watch(activeLoansProvider)) {
    final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (i.dueDate.isBefore(range.start) || i.dueDate.isAfter(range.end)) continue;
      if (i.amountPaid <= 0) continue;
      lines.add((
        kind: MoneyFlowKind.loan,
        date: i.dueDate,
        title: loan.name ?? 'Loan',
        amount: i.amountPaid,
        categoryLabel: 'Loan',
        accountLabel: null,
      ));
    }
  }

  final bills = ref.watch(billsStreamProvider).value ?? const [];
  for (final bill in bills) {
    final occurrences = ref.watch(billOccurrencesStreamProvider(bill.id)).value ?? const [];
    for (final o in occurrences) {
      if (o.status == BillStatus.skipped) continue;
      if (o.dueDate.isBefore(range.start) || o.dueDate.isAfter(range.end)) continue;
      if (o.amountPaid <= 0) continue;
      lines.add((
        kind: MoneyFlowKind.bill,
        date: o.dueDate,
        title: bill.name,
        amount: o.amountPaid,
        categoryLabel: 'Bill',
        accountLabel: null,
      ));
    }
  }

  lines.sort((a, b) => b.date.compareTo(a.date));
  return lines;
});

/// [moneyInLinesForRangeFamilyProvider] bound to the Cash Flow screen's own
/// selected [cashFlowDateRangeProvider] — what the Cash Flow screen and its
/// Money In detail screen actually watch.
final moneyInLinesForRangeProvider = Provider<List<MoneyFlowLine>>((ref) {
  final period = ref.watch(cashFlowDateRangeProvider);
  final range = ref.watch(resolvedCashFlowRangeProvider);
  return ref.watch(moneyInLinesForRangeFamilyProvider((period: period, range: range)));
});

/// [moneyOutLinesForRangeFamilyProvider] bound to the Cash Flow screen's own
/// selected [cashFlowDateRangeProvider] — what the Cash Flow screen and its
/// Money Out detail screen actually watch.
final moneyOutLinesForRangeProvider = Provider<List<MoneyFlowLine>>((ref) {
  final period = ref.watch(cashFlowDateRangeProvider);
  final range = ref.watch(resolvedCashFlowRangeProvider);
  return ref.watch(moneyOutLinesForRangeFamilyProvider((period: period, range: range)));
});

/// Cash Flow Summary (Section 5), generalized from
/// [cashFlowThisMonthProvider] to read [resolvedCashFlowRangeProvider]
/// instead of always the current calendar month. `moneyIn`/`moneyOut` are
/// sums of [moneyInLinesForRangeProvider]/[moneyOutLinesForRangeProvider] —
/// never a separately-filtered calculation — so this figure and the Money
/// In/Out detail screens are guaranteed to agree by construction. Kept as a
/// separate provider (rather than rewriting [cashFlowThisMonthProvider] in
/// place) so nothing else that still depends on strict "this calendar
/// month" behavior is affected.
final cashFlowForRangeProvider = Provider<CashFlowSummary>((ref) {
  final moneyIn = ref.watch(moneyInLinesForRangeProvider).fold(0.0, (sum, l) => sum + l.amount);
  final moneyOut = ref.watch(moneyOutLinesForRangeProvider).fold(0.0, (sum, l) => sum + l.amount);
  return (moneyIn: moneyIn, moneyOut: moneyOut, net: moneyIn - moneyOut);
});

// ---------------------------------------------------------------------------
// My Expenses (Feature: separate from the date range filter above, but
// reads it)
// ---------------------------------------------------------------------------
//
// "How much did I personally spend during the selected period?" — my own
// share only. Explicitly NOT the same number as Section 5's Money Out
// above: Money Out also includes EMI/Loan/Bill payments (scheduled
// obligations, not spending choices), and for a shared expense it counts
// the FULL amount (since that's what actually left the account), not just
// my share of it.

/// My Expenses' breakdown for the selected range — reduces
/// [calculableTransactionsProvider] filtered to
/// [resolvedCashFlowRangeProvider] through the same
/// [myExpenseBreakdownForTransactionsProvider] Reports already uses, so the
/// Expense-vs-plain-transaction / split-share math is never re-derived here.
final myExpensesForRangeProvider = Provider<MyExpenseBreakdown>((ref) {
  final period = ref.watch(cashFlowDateRangeProvider);
  final range = ref.watch(resolvedCashFlowRangeProvider);
  final transactions = ref.watch(calculableTransactionsProvider);
  final rangeTransactions = transactions.where((t) {
    if (t.isDeleted) return false;
    final bucketDate = period.bucketDateFor(t);
    return !bucketDate.isBefore(range.start) && !bucketDate.isAfter(range.end);
  }).toList();
  return ref.watch(myExpenseBreakdownForTransactionsProvider(rangeTransactions));
});

/// Every individual [MyExpenseLine] behind [myExpensesForRangeProvider]'s
/// total — the single list [myExpensesByCategoryProvider] and the My
/// Expenses history/category-detail screens all read, so the total, the
/// per-category totals, and the drill-down history can never disagree: each
/// is just a different fold/filter over this exact same list. Bucketed by
/// [CashFlowPeriod.bucketDateFor], the same rule every other range-scoped
/// Cash Flow line list uses, so this always matches
/// [myExpensesForRangeProvider]'s own [Transaction.effectiveMonth]-vs-
/// [Transaction.dateTime] choice for the selected period.
final myExpenseLinesForRangeProvider = Provider<List<MyExpenseLine>>((ref) {
  final period = ref.watch(cashFlowDateRangeProvider);
  final range = ref.watch(resolvedCashFlowRangeProvider);
  final categoriesById = {for (final c in ref.watch(categoriesStreamProvider).value ?? const []) c.id: c};
  final accountsById = {for (final a in ref.watch(accountsStreamProvider).value ?? const []) a.id: a};
  final expenseByTransactionId = {
    for (final e in ref.watch(expensesStreamProvider).value ?? const []) e.transactionId: e,
  };

  final lines = <MyExpenseLine>[];
  final transactions = ref.watch(calculableTransactionsProvider);
  for (final t in transactions) {
    if (t.isDeleted || t.type != TransactionType.expense) continue;
    final bucketDate = period.bucketDateFor(t);
    if (bucketDate.isBefore(range.start) || bucketDate.isAfter(range.end)) continue;

    final expense = expenseByTransactionId[t.id];
    final myShare = expense?.myShare ?? t.amount;
    if (myShare <= 0) continue;
    final categoryId = expense?.categoryId ?? t.categoryId;

    lines.add((
      transactionId: t.id,
      date: t.dateTime,
      title: expense?.description.isNotEmpty == true ? expense!.description : (t.description.isNotEmpty ? t.description : 'Expense'),
      myShare: myShare,
      totalAmount: expense?.isSplit == true ? expense!.totalAmount : null,
      isSplit: expense?.isSplit ?? false,
      categoryId: categoryId,
      categoryLabel: categoriesById[categoryId]?.name,
      accountLabel: accountsById[t.accountId]?.name,
      notes: expense?.notes ?? '',
    ));
  }

  lines.sort((a, b) => b.date.compareTo(a.date));
  return lines;
});

/// One category's total within [myExpenseLinesForRangeProvider] — sorted
/// highest amount first for the My Expenses history's category list.
typedef MyExpenseCategoryTotal = ({String categoryId, String categoryLabel, double amount});

/// [myExpenseLinesForRangeProvider] grouped by category and summed — always
/// reconciles with [myExpensesForRangeProvider].total by construction, since
/// both fold over the exact same line list.
final myExpensesByCategoryProvider = Provider<List<MyExpenseCategoryTotal>>((ref) {
  final lines = ref.watch(myExpenseLinesForRangeProvider);
  final totals = <String, double>{};
  final labels = <String, String>{};
  for (final line in lines) {
    totals[line.categoryId] = (totals[line.categoryId] ?? 0) + line.myShare;
    labels[line.categoryId] = line.categoryLabel ?? 'Uncategorized';
  }
  final result = [
    for (final entry in totals.entries) (categoryId: entry.key, categoryLabel: labels[entry.key]!, amount: entry.value),
  ];
  result.sort((a, b) => b.amount.compareTo(a.amount));
  return result;
});

/// [myExpenseLinesForRangeProvider] filtered to a single [categoryId] — the
/// My Expenses category drill-down's data source, sorted newest first same
/// as the parent list.
final myExpensesForCategoryProvider = Provider.family<List<MyExpenseLine>, String>((ref, categoryId) {
  return ref.watch(myExpenseLinesForRangeProvider).where((l) => l.categoryId == categoryId).toList();
});
