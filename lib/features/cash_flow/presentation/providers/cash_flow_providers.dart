import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../shared/domain/payment_urgency.dart';
import '../../../bills/domain/bill_status.dart';
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
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// Aggregation providers for the Dashboard's "Cash Flow Center" sections.
/// Every provider below strictly composes existing providers/model getters
/// — no new Firestore reads, no reimplemented remaining-amount or status
/// math. See `lib/features/*/domain/*.dart` for the underlying `.status`/
/// `.remainingAmount` computations this file only ever reads, never repeats.

/// A single row's due/paid/remaining figures for Section 1 ("Payments Due
/// This Month").
typedef DueCategoryBreakdown = ({double due, double paid, double remaining});

const _zeroBreakdown = (due: 0.0, paid: 0.0, remaining: 0.0);

DueCategoryBreakdown _combine(Iterable<DueCategoryBreakdown> rows) {
  final due = rows.fold(0.0, (sum, r) => sum + r.due);
  final paid = rows.fold(0.0, (sum, r) => sum + r.paid);
  return (due: due, paid: paid, remaining: due - paid);
}

/// Sum of this-month installment due/paid across every active EMI.
final emiDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final emis = ref.watch(dueThisMonthEmisProvider);
  var due = 0.0, paid = 0.0;
  for (final emi in emis) {
    final thisMonth = ref.watch(thisMonthInstallmentsProvider(emi.scheduleId));
    due += thisMonth.fold(0.0, (s, i) => s + i.amountDue);
    paid += thisMonth.fold(0.0, (s, i) => s + i.amountPaid);
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Sum of this-month installment due/paid across every active Loan.
final loanDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final loans = ref.watch(activeLoansProvider);
  var due = 0.0, paid = 0.0;
  for (final loan in loans) {
    final thisMonth = ref.watch(thisMonthInstallmentsProvider(loan.scheduleId));
    due += thisMonth.fold(0.0, (s, i) => s + i.amountDue);
    paid += thisMonth.fold(0.0, (s, i) => s + i.amountPaid);
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Sum of this-month bill amount/paid, excluding skipped occurrences.
final billsDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final bills = ref.watch(billsStreamProvider).value ?? const [];
  final now = DateTime.now();
  var due = 0.0, paid = 0.0;
  for (final b in bills) {
    if (!b.dueDate.isSameMonth(now) || b.status == BillStatus.skipped) continue;
    due += b.amount;
    paid += b.amountPaid;
  }
  return (due: due, paid: paid, remaining: due - paid);
});

/// Sum of this-month statement total/paid across every card, excluding
/// already-paid statements.
final creditCardDueThisMonthBreakdownProvider = Provider<DueCategoryBreakdown>((ref) {
  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  final now = DateTime.now();
  var due = 0.0, paid = 0.0;
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    for (final s in statements) {
      if (!s.dueDate.isSameMonth(now) || s.status == StatementStatus.paid) continue;
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

/// Split expenses still owed to me.
final splitExpensesReceivableProvider = Provider<ReceivableCategoryBreakdown>((ref) {
  final pending = ref.watch(pendingSplitExpensesProvider);
  final amount = ref.watch(totalPendingSplitAmountProvider);
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
      final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
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

/// One merged row in Section 4's upcoming-payments timeline.
typedef UpcomingPaymentItem = ({
  UpcomingPaymentKind kind,
  String title,
  DateTime dueDate,
  double amountDue,
  double remaining,
  PaymentUrgency urgency,
  String routeId,
});

/// Every unpaid, non-skipped EMI/Loan installment, Bill, and Credit Card
/// statement, merged and sorted with overdue items always first (regardless
/// of date), then ascending due date — Section 4's data source.
final upcomingPaymentsTimelineProvider = Provider<List<UpcomingPaymentItem>>((ref) {
  final items = <UpcomingPaymentItem>[];

  for (final emi in ref.watch(activeEmisProvider)) {
    final installments = ref.watch(installmentsStreamProvider(emi.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (i.status == InstallmentStatus.paid || i.isSkipped) continue;
      items.add((
        kind: UpcomingPaymentKind.emi,
        title: emi.name,
        dueDate: i.dueDate,
        amountDue: i.amountDue,
        remaining: i.remainingAmount,
        urgency: PaymentUrgencyX.fromInstallmentStatus(i.status),
        routeId: emi.id,
      ));
    }
  }

  for (final loan in ref.watch(activeLoansProvider)) {
    final installments = ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [];
    for (final i in installments) {
      if (i.status == InstallmentStatus.paid || i.isSkipped) continue;
      items.add((
        kind: UpcomingPaymentKind.loan,
        title: loan.name ?? 'Loan',
        dueDate: i.dueDate,
        amountDue: i.amountDue,
        remaining: i.remainingAmount,
        urgency: PaymentUrgencyX.fromInstallmentStatus(i.status),
        routeId: loan.id,
      ));
    }
  }

  final bills = ref.watch(billsStreamProvider).value ?? const [];
  for (final b in bills) {
    if (b.status == BillStatus.paid || b.status == BillStatus.skipped) continue;
    items.add((
      kind: UpcomingPaymentKind.bill,
      title: b.name,
      dueDate: b.dueDate,
      amountDue: b.amount,
      remaining: b.remainingAmount,
      urgency: PaymentUrgencyX.fromBillStatus(b.status),
      routeId: b.id,
    ));
  }

  final cards = ref.watch(creditCardsStreamProvider).value ?? const [];
  for (final card in cards) {
    final statements = ref.watch(statementsStreamProvider(card.id)).value ?? const [];
    for (final s in statements) {
      if (s.status == StatementStatus.paid) continue;
      items.add((
        kind: UpcomingPaymentKind.creditCard,
        title: card.lastFourDigits != null ? 'Card •••• ${card.lastFourDigits}' : 'Credit Card',
        dueDate: s.dueDate,
        amountDue: s.totalAmount,
        remaining: s.remainingAmount,
        urgency: PaymentUrgencyX.fromStatementStatus(s.status),
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

/// This month's cash flow. EMI/Bill/Loan payments never post a `Transaction`
/// (confirmed by reading `EmiRepository`/`BillRepository`'s payment-recording
/// methods), so [moneyOut] must add their paid amounts explicitly on top of
/// expense transactions rather than assuming those payments are already
/// included.
final cashFlowThisMonthProvider = Provider<CashFlowSummary>((ref) {
  final now = DateTime.now();
  final transactions = ref.watch(transactionsStreamProvider).value ?? const [];
  final monthTransactions = transactions.where((t) => t.dateTime.isSameMonth(now) && !t.isDeleted);

  final income = monthTransactions
      .where((t) => t.type == TransactionType.income)
      .fold(0.0, (sum, t) => sum + t.amount);
  final expenses = monthTransactions
      .where((t) => t.type == TransactionType.expense)
      .fold(0.0, (sum, t) => sum + t.amount);

  final moneyReceived = ref.watch(moneyReceivedForRangeProvider((start: now.startOfMonth, end: now.endOfMonth)));
  final emiPaid = ref.watch(emiPaidThisMonthProvider);
  final loanPaid = ref.watch(loanDueThisMonthBreakdownProvider).paid;
  final billsPaid = ref.watch(billsDueThisMonthBreakdownProvider).paid;

  final moneyIn = income + moneyReceived;
  final moneyOut = expenses + emiPaid + loanPaid + billsPaid;
  return (moneyIn: moneyIn, moneyOut: moneyOut, net: moneyIn - moneyOut);
});
