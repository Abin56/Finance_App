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
import '../../../reports/domain/reports_period.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/cash_flow_preset.dart';

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

/// The Cash Flow Center's globally selected period — every date-dependent
/// section (Payments Due, Money To Receive's split-expense figures,
/// Upcoming Payments, This Period Cash Flow, My Expenses) reads this one
/// provider rather than each re-deriving "now"/"this month" independently.
/// Credit Card Statement Summary (Section 3) deliberately does not depend
/// on this — a statement's "current cycle" is a single fixed thing, not a
/// window a date range can meaningfully re-slice.
final cashFlowSelectionProvider = StateProvider<CashFlowSelection>((ref) => CashFlowSelection.initial());

/// Convenience accessor for just the resolved [DateRange] of the current
/// selection — most range-aware providers below only need this, not the
/// preset/label.
final cashFlowRangeProvider = Provider<DateRange>((ref) => ref.watch(cashFlowSelectionProvider).range);

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

/// Range-generic counterpart of [emiDueThisMonthBreakdownProvider] — the
/// carry-over/current classification still comes from the same
/// `CycleEngine` (still relative to *today*, not the selected range, since
/// "what's still unpaid from a prior cycle" is a today-relative fact), but
/// which items count as "due" is filtered by [range] instead of hardcoded
/// to the calendar month containing `DateTime.now()`.
final emiDueForRangeBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final emis = ref.watch(activeEmisProvider);
  var due = 0.0, paid = 0.0;
  for (final emi in emis) {
    final view = ref.watch(emiCycleViewRecordProvider(emi));
    final carriedOver = view.previousCyclePending.where((i) => range.contains(i.dueDate));
    final current = view.current.where((i) => range.contains(i.dueDate));
    for (final i in {...carriedOver, ...current}) {
      due += i.amountDue;
      paid += i.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Range-generic counterpart of [loanDueThisMonthBreakdownProvider] — see
/// [emiDueForRangeBreakdownProvider] for the carry-over/range split.
final loanDueForRangeBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final loans = ref.watch(activeLoansProvider);
  var due = 0.0, paid = 0.0;
  for (final loan in loans) {
    final view = ref.watch(loanCycleViewRecordProvider(loan));
    final carriedOver = view.previousCyclePending.where((i) => range.contains(i.dueDate));
    final current = view.current.where((i) => range.contains(i.dueDate));
    for (final i in {...carriedOver, ...current}) {
      due += i.amountDue;
      paid += i.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Range-generic counterpart of [billsDueThisMonthBreakdownProvider] — see
/// [emiDueForRangeBreakdownProvider] for the carry-over/range split.
final billsDueForRangeBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  var due = 0.0, paid = 0.0;
  for (final bill in bills) {
    final view = ref.watch(billOccurrenceCycleViewProvider(bill.id));
    final carriedOver = view.previousCyclePending.where((o) => range.contains(o.dueDate));
    final current = view.current != null && range.contains(view.current!.dueDate) ? [view.current!] : const [];
    for (final o in {...carriedOver, ...current}) {
      if (o.status == BillStatus.skipped) continue;
      due += o.amount;
      paid += o.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Range-generic counterpart of [creditCardDueThisMonthBreakdownProvider] —
/// see [emiDueForRangeBreakdownProvider] for the carry-over/range split.
final creditCardDueForRangeBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  var due = 0.0, paid = 0.0;
  for (final card in cards) {
    final view = ref.watch(statementCycleViewProvider(card.id));
    final carriedOver = view.previousCyclePending.where((s) => range.contains(s.dueDate));
    final current = view.current != null && range.contains(view.current!.dueDate) ? [view.current!] : const [];
    for (final s in {...carriedOver, ...current}) {
      if (s.status == StatementStatus.paid) continue;
      due += s.totalAmount;
      paid += s.amountPaid;
    }
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Range-generic roll-up for Section 1's headline Total Due/Paid/Remaining,
/// scoped to [cashFlowRangeProvider] instead of the calendar month.
final totalDueForRangeProvider = Provider<DueCategoryBreakdown>((ref) {
  return _combine([
    ref.watch(creditCardDueForRangeBreakdownProvider),
    ref.watch(emiDueForRangeBreakdownProvider),
    ref.watch(loanDueForRangeBreakdownProvider),
    ref.watch(billsDueForRangeBreakdownProvider),
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

/// Range-generic counterpart of [splitExpensesReceivableProvider] — scopes
/// to split expenses whose own [Expense.date] falls in [range]. People
/// Pending Payments and Loan Recoveries stay whole-balance figures (a
/// person's/loan's outstanding balance isn't naturally sliceable by "which
/// date range created it" the way a single expense's date is), matching
/// how Reports treats balances vs. period activity.
final splitExpensesReceivableForRangeProvider = Provider<ReceivableCategoryBreakdown>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final pending = ref.watch(pendingSplitExpensesProvider).where(
        (e) => range.contains(e.date) && e.participants.any((p) => !p.isMe && p.personId == null),
      );
  var amount = 0.0;
  var count = 0;
  for (final expense in pending) {
    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    for (final participant in expense.participants) {
      if (participant.isMe || participant.personId != null) continue;
      final installment = installments.where((i) => i.id == participant.installmentId).firstOrNull;
      if (installment != null) amount += installment.remainingAmount;
    }
    count++;
  }
  return (amount: amount, count: count);
});

/// Range-generic roll-up for Section 2's headline Total, scoped to
/// [cashFlowRangeProvider] for split expenses only (see
/// [splitExpensesReceivableForRangeProvider]).
final totalMoneyToReceiveForRangeProvider = Provider<double>((ref) {
  return ref.watch(splitExpensesReceivableForRangeProvider).amount +
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

/// Range-generic counterpart of [upcomingPaymentsTimelineProvider] — same
/// merged/sorted list, filtered to items whose [UpcomingPaymentItem.dueDate]
/// falls within [cashFlowRangeProvider]. Urgency/carry-over classification
/// is untouched (still relative to *today*, matching each module's own
/// screen) — only which items are shown is scoped to the selected range.
final upcomingPaymentsForRangeProvider = Provider<List<UpcomingPaymentItem>>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final items = ref.watch(upcomingPaymentsTimelineProvider).where((i) => range.contains(i.dueDate)).toList();
  return items;
});

/// Section 5's Money In/Out/Net figures.
typedef CashFlowSummary = ({double moneyIn, double moneyOut, double net});

/// Sum of this-month (calendar-month, not carry-over-merged) installment
/// `amountPaid` across every active Loan — kept separate from
/// [loanDueThisMonthBreakdownProvider] so [cashFlowThisMonthProvider] isn't
/// affected by Section 1's overdue-carry-over merge; paying off an old
/// installment this month is real Money Out, but it belongs to the month it
/// was paid in, not counted again via a due-date-based lookup.
final _loanPaidThisMonthProvider = Provider<double>((ref) {
  final loans = ref.watch(activeLoansProvider);
  var paid = 0.0;
  for (final loan in loans) {
    final thisMonth = ref.watch(thisMonthInstallmentsProvider(loan.scheduleId));
    paid += thisMonth.fold(0.0, (s, i) => s + i.amountPaid);
  }
  return paid;
});

/// Sum of this-month (calendar-month) bill `amountPaid` — see
/// [_loanPaidThisMonthProvider] for why this stays independent of
/// [billsDueThisMonthBreakdownProvider].
final _billsPaidThisMonthProvider = Provider<double>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final now = DateTime.now();
  var paid = 0.0;
  for (final bill in bills) {
    final occurrences = ref.watch(billOccurrencesStreamProvider(bill.id)).value ?? const [];
    for (final o in occurrences) {
      if (!o.dueDate.isSameMonth(now) || o.status == BillStatus.skipped) continue;
      paid += o.amountPaid;
    }
  }
  return paid;
});

/// This month's cash flow. EMI/Bill/Loan payments never post a `Transaction`
/// (confirmed by reading `EmiRepository`/`BillRepository`'s payment-recording
/// methods), so [moneyOut] must add their paid amounts explicitly on top of
/// expense transactions rather than assuming those payments are already
/// included.
final cashFlowThisMonthProvider = Provider<CashFlowSummary>((ref) {
  final now = DateTime.now();
  final transactions = ref.watch(calculableTransactionsProvider);
  // Transfers between the user's own accounts aren't real income/expense —
  // excluded so a transfer's two legs don't inflate both Money In and
  // Money Out.
  final monthTransactions = transactions.where((t) => t.effectiveMonth.isSameMonth(now) && !t.isDeleted && !t.isTransfer);

  final income = monthTransactions
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);
  final expenses = monthTransactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  final moneyReceived = ref.watch(moneyReceivedForRangeProvider((start: now.startOfMonth, end: now.endOfMonth)));
  final emiPaid = ref.watch(emiPaidThisMonthProvider);
  final loanPaid = ref.watch(_loanPaidThisMonthProvider);
  final billsPaid = ref.watch(_billsPaidThisMonthProvider);

  final moneyIn = income + moneyReceived;
  final moneyOut = expenses + emiPaid + loanPaid + billsPaid;
  return (moneyIn: moneyIn, moneyOut: moneyOut, net: moneyIn - moneyOut);
});

/// Sum of `amountPaid` across every active EMI's installments whose
/// [Installment.dueDate] falls in [range] — range-generic counterpart of
/// [emiPaidThisMonthProvider], filtering the same underlying installment
/// stream by [DateRange.contains] instead of [DateTimeX.isSameMonth].
final _emiPaidForRangeProvider = Provider<double>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final emis = ref.watch(activeEmisProvider);
  var paid = 0.0;
  for (final emi in emis) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (range.contains(i.dueDate)) paid += i.amountPaid;
    }
  }
  return paid;
});

/// Range-generic counterpart of [_loanPaidThisMonthProvider].
final _loanPaidForRangeProvider = Provider<double>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final loans = ref.watch(activeLoansProvider);
  var paid = 0.0;
  for (final loan in loans) {
    final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (range.contains(i.dueDate)) paid += i.amountPaid;
    }
  }
  return paid;
});

/// Range-generic counterpart of [_billsPaidThisMonthProvider].
final _billsPaidForRangeProvider = Provider<double>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  var paid = 0.0;
  for (final bill in bills) {
    final occurrences = ref.watch(billOccurrencesStreamProvider(bill.id)).value ?? const [];
    for (final o in occurrences) {
      if (!range.contains(o.dueDate) || o.status == BillStatus.skipped) continue;
      paid += o.amountPaid;
    }
  }
  return paid;
});

/// Range-generic counterpart of [cashFlowThisMonthProvider] — Section 5
/// ("Cash Flow Summary") scoped to [cashFlowRangeProvider] instead of the
/// calendar month containing `DateTime.now()`. Same accounting rules
/// (transfers/deleted/excluded excluded, `effectiveMonth` respected, EMI/
/// Loan/Bill payments added on top since they never post their own
/// `Transaction` — see [cashFlowThisMonthProvider]'s doc comment).
final cashFlowForRangeProvider = Provider<CashFlowSummary>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final transactions = ref.watch(calculableTransactionsProvider);
  final rangeTransactions = transactions.where((t) => range.contains(t.effectiveMonth) && !t.isDeleted && !t.isTransfer);

  final income = rangeTransactions
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);
  final expenses = rangeTransactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  final moneyReceived = ref.watch(moneyReceivedForRangeProvider((start: range.start, end: range.end)));
  final emiPaid = ref.watch(_emiPaidForRangeProvider);
  final loanPaid = ref.watch(_loanPaidForRangeProvider);
  final billsPaid = ref.watch(_billsPaidForRangeProvider);

  final moneyIn = income + moneyReceived;
  final moneyOut = expenses + emiPaid + loanPaid + billsPaid;
  return (moneyIn: moneyIn, moneyOut: moneyOut, net: moneyIn - moneyOut);
});

/// Section 6 — "My Expenses". Answers "how much did I personally spend in
/// the selected range", as distinct from [cashFlowForRangeProvider]'s
/// broader Money Out (which also includes EMI/Loan/Bill payments — real
/// cash leaving, but not a personal-spending figure). Reuses
/// [myExpenseBreakdownForTransactionsProvider] (`Expense.myShare`) — the
/// exact same join Reports' "My Expense" card uses — over the same
/// `calculableTransactionsProvider`+`effectiveMonth`+transfer-exclusion
/// filter as [cashFlowForRangeProvider], so a shared expense's other
/// participants' shares are never counted here, and EMI/Loan/Bill payments
/// (which aren't `Transaction`s of type expense tied to an `Expense`
/// document) can never leak into this figure either.
final myExpensesForRangeProvider = Provider<MyExpenseBreakdown>((ref) {
  final range = ref.watch(cashFlowRangeProvider);
  final transactions = ref.watch(calculableTransactionsProvider);
  final rangeExpenseTransactions = transactions
      .where((t) => range.contains(t.effectiveMonth) && !t.isDeleted && !t.isTransfer && t.type == TransactionType.expense)
      .toList();
  return ref.watch(myExpenseBreakdownForTransactionsProvider(rangeExpenseTransactions));
});
