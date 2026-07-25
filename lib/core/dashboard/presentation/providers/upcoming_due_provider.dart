import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../extensions/date_extensions.dart';
import '../../../payment_schedule/domain/cycle_engine.dart';
import '../../../payment_schedule/domain/installment_cycle_item.dart';
import '../../../../features/bills/domain/bill_status.dart';
import '../../../../features/bills/presentation/providers/bill_occurrence_providers.dart';
import '../../../../features/bills/presentation/providers/bill_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/expense/presentation/providers/expense_providers.dart';
import '../../../../features/lending/presentation/providers/loan_providers.dart';
import '../../../../features/people/presentation/providers/person_timeline_providers.dart';
import '../../../../shared/domain/payment_urgency.dart';

/// Which feature an [UpcomingDueItem] came from, for routing on tap.
enum UpcomingDueKind { creditCard, emi, loan, bill, splitExpense }

/// The pay cycle window [upcomingDueProvider] classifies items against —
/// [start]/[end] of the *current* cycle (e.g. 17 Jul → 17 Aug).
typedef UpcomingDueCycle = ({DateTime start, DateTime end});

/// One row in the "Spend This Pay Period" card's Upcoming Due section.
/// [secondaryRouteId] is only populated for [UpcomingDueKind.creditCard]
/// (the statement id, alongside [routeId] as the card id) since that's the
/// only kind whose detail screen needs two path segments. [isCarriedOver]
/// marks an item whose due date falls before the current cycle even
/// started — still unpaid from a prior pay period.
typedef UpcomingDueItem = ({
  UpcomingDueKind kind,
  String title,
  DateTime dueDate,
  double remaining,
  PaymentUrgency urgency,
  bool isCarriedOver,
  String routeId,
  String? secondaryRouteId,
});

/// Every unpaid Credit Card statement, EMI/Loan installment, Bill, and
/// split-expense settlement due on or before [cycle]'s end — the Upcoming
/// Due section of the pay-period card. Purely composes each feature's
/// existing `*CycleViewProvider` (Credit Cards' `statementCycleViewProvider`,
/// EMI's `emiCycleViewRecordProvider`, Loan's `loanCycleViewRecordProvider`,
/// Bills' `billOccurrenceCycleViewProvider`), each of which already runs the
/// shared [CycleEngine] against that module's own [CycleAnchor] — no status,
/// remaining-amount, or carry-forward math is reimplemented here.
///
/// [UpcomingDueItem.isCarriedOver] mirrors exactly what each module's own
/// screen already shows as "Previous Cycle Pending" — this provider only
/// re-groups those same classified items into one cross-feature list, it
/// never derives the classification itself. Every kind now shares this one
/// carry-forward source of truth; there is no cutoff logic of this
/// provider's own left to diverge from module to module.
///
/// Deliberately excludes plain People/Ledger balances: a [Person] carries a
/// running balance with no due date anywhere in its model, so it has no
/// date to be filtered/sorted by here. Money owed *through a split expense*
/// still appears, since each participant's share is tracked by a dated
/// [Installment] like every other kind in this list.
final upcomingDueProvider = Provider.family<List<UpcomingDueItem>, UpcomingDueCycle>((ref, cycle) {
  final cutoff = cycle.end.dateOnly;
  final items = <UpcomingDueItem>[];

  for (final card in ref.watch(activeCreditCardsProvider)) {
    final view = ref.watch(statementCycleViewProvider(card.id));
    final relevant = [...view.previousCyclePending, if (view.current != null) view.current!];
    for (final statement in relevant) {
      if (statement.remainingAmount <= 0) continue;
      if (statement.dueDate.dateOnly.isAfter(cutoff)) continue;
      final isCarriedOver = view.previousCyclePending.contains(statement);
      items.add((
        kind: UpcomingDueKind.creditCard,
        title: card.lastFourDigits != null ? 'Card •••• ${card.lastFourDigits}' : 'Credit Card',
        dueDate: statement.dueDate,
        remaining: statement.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromStatementStatus(statement.status),
        isCarriedOver: isCarriedOver,
        routeId: card.id,
        secondaryRouteId: statement.id,
      ));
    }
  }

  for (final emi in ref.watch(activeEmisProvider)) {
    final view = ref.watch(emiCycleViewRecordProvider(emi));
    final relevant = [...view.previousCyclePending, ...view.current];
    for (final installment in relevant) {
      if (installment.remainingAmount <= 0 || installment.isSkipped) continue;
      if (installment.dueDate.dateOnly.isAfter(cutoff)) continue;
      final isCarriedOver = view.previousCyclePending.contains(installment);
      items.add((
        kind: UpcomingDueKind.emi,
        title: emi.name,
        dueDate: installment.dueDate,
        remaining: installment.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromInstallmentStatus(installment.status),
        isCarriedOver: isCarriedOver,
        routeId: emi.id,
        secondaryRouteId: null,
      ));
    }
  }

  for (final loan in ref.watch(activeLoansProvider)) {
    final view = ref.watch(loanCycleViewRecordProvider(loan));
    final relevant = [...view.previousCyclePending, ...view.current];
    for (final installment in relevant) {
      if (installment.remainingAmount <= 0 || installment.isSkipped) continue;
      if (installment.dueDate.dateOnly.isAfter(cutoff)) continue;
      final isCarriedOver = view.previousCyclePending.contains(installment);
      items.add((
        kind: UpcomingDueKind.loan,
        title: loan.name ?? 'Loan',
        dueDate: installment.dueDate,
        remaining: installment.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromInstallmentStatus(installment.status),
        isCarriedOver: isCarriedOver,
        routeId: loan.id,
        secondaryRouteId: null,
      ));
    }
  }

  final bills = ref.watch(billsStreamProvider).value ?? const [];
  for (final bill in bills) {
    final view = ref.watch(billOccurrenceCycleViewProvider(bill.id));
    final relevant = [...view.previousCyclePending, if (view.current != null) view.current!];
    for (final occurrence in relevant) {
      if (occurrence.status == BillStatus.skipped || occurrence.remainingAmount <= 0) continue;
      if (occurrence.dueDate.dateOnly.isAfter(cutoff)) continue;
      final isCarriedOver = view.previousCyclePending.contains(occurrence);
      items.add((
        kind: UpcomingDueKind.bill,
        title: bill.name,
        dueDate: occurrence.dueDate,
        remaining: occurrence.remainingAmount,
        urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromBillStatus(occurrence.status),
        isCarriedOver: isCarriedOver,
        routeId: bill.id,
        secondaryRouteId: null,
      ));
    }
  }

  // Split-expense participants have no single owning schedule/card to key a
  // dedicated `*CycleViewProvider` off of (unlike EMI/Loan/Bills), so each
  // pending participant's installment is classified individually here —
  // still via the shared `CycleEngine` + `InstallmentCycleItem` adapter,
  // anchored at the same `personCycleAnchor` the People module's own
  // `personCycleViewProvider` uses, since a split expense's carry-forward
  // boundary is the same Contact Ledger cycle as the person it's owed to.
  for (final pending in ref.watch(pendingSplitParticipantsProvider)) {
    if (pending.participant.isMe) continue;
    final installment = pending.installment;
    if (installment.isSkipped) continue;
    if (installment.dueDate.dateOnly.isAfter(cutoff)) continue;
    final classification = CycleEngine.classifyForCarryForward(
      [InstallmentCycleItem(installment)],
      personCycleAnchor,
    );
    final isCarriedOver = classification.previousCyclePending.isNotEmpty;
    items.add((
      kind: UpcomingDueKind.splitExpense,
      title: '${pending.expense.description} · ${pending.participant.name}',
      dueDate: installment.dueDate,
      remaining: installment.remainingAmount,
      urgency: isCarriedOver ? PaymentUrgency.carriedForward : PaymentUrgencyX.fromInstallmentStatus(installment.status),
      isCarriedOver: isCarriedOver,
      routeId: pending.expense.transactionId,
      secondaryRouteId: null,
    ));
  }

  items.sort((a, b) {
    final aOverdue = a.urgency == PaymentUrgency.overdue;
    final bOverdue = b.urgency == PaymentUrgency.overdue;
    if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
    return a.dueDate.compareTo(b.dueDate);
  });
  return items;
});
