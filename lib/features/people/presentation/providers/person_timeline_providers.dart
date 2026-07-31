import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/payment_schedule/domain/cycle_anchor.dart';
import '../../../../core/payment_schedule/domain/cycle_engine.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../expense/presentation/providers/expense_providers.dart';
import '../../../lending/presentation/providers/loan_providers.dart';
import '../../domain/person_cycle_summary.dart';
import '../../domain/person_overall_totals.dart';
import '../../domain/person_timeline_builder.dart';
import '../../domain/person_timeline_cycle_item.dart';
import '../../domain/person_timeline_entry.dart';
import 'people_providers.dart';

/// Every payment recorded across a loan's whole installment schedule —
/// fans out over the schedule's installments (payments are stored per
/// installment, not per schedule) since no schedule-wide payment stream
/// exists on `InstallmentPaymentRepository`.
final _loanPaymentsProvider = Provider.autoDispose.family<List<InstallmentPayment>, String>((ref, scheduleId) {
  final installments = ref.watch(installmentsStreamProvider(scheduleId)).value ?? const [];
  return [
    for (final installment in installments)
      ...ref.watch(installmentPaymentsStreamProvider((scheduleId: scheduleId, installmentId: installment.id))).value ??
          const [],
  ];
});

/// One person's complete financial timeline — folds their [LedgerEntry]s
/// (money given/borrowed/received/repaid/adjustments, and — since
/// `ExpenseRepository` already posts ledger entries for person-linked
/// expense participants — assigned/split expenses too) together with their
/// [Loan]s and loan payments, via [PersonTimelineBuilder]. This is the one
/// place all of a person's money-interaction sources are pulled together.
final personTimelineProvider = Provider.autoDispose.family<List<PersonTimelineEntry>, String>((ref, personId) {
  final ledgerEntries = ref.watch(ledgerStreamProvider(personId)).value ?? const [];
  final loans = ref.watch(loansForPersonProvider(personId));
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];

  final loanData = [
    for (final loan in loans)
      LoanTimelineData(
        loan: loan,
        installments: ref.watch(installmentsStreamProvider(loan.scheduleId)).value ?? const [],
        payments: ref.watch(_loanPaymentsProvider(loan.scheduleId)),
      ),
  ];

  final participantCountByTransactionRef = {
    for (final expense in expenses) expense.transactionId: expense.participants.length,
  };

  final otherParticipantNamesByTransactionRef = {
    for (final expense in expenses)
      expense.transactionId: [
        for (final participant in expense.participants)
          if (!participant.isMe && participant.personId != personId) participant.name,
      ],
  };

  final installmentByTransactionRef = <String, Installment>{};
  for (final expense in expenses) {
    if (expense.scheduleId == null) continue;
    final participant = expense.participants.where((p) => p.personId == personId).firstOrNull;
    if (participant?.installmentId == null) continue;
    final installments = ref.watch(installmentsStreamProvider(expense.scheduleId!)).value ?? const [];
    final installment = installments.where((i) => i.id == participant!.installmentId).firstOrNull;
    if (installment == null) continue;
    installmentByTransactionRef[expense.transactionId] = installment;
  }

  final referencedTransactions = ref.watch(personReferencedTransactionsProvider(personId));

  return PersonTimelineBuilder.build(
    ledgerEntries: ledgerEntries,
    loans: loanData,
    referencedTransactions: referencedTransactions,
    participantCountByTransactionRef: participantCountByTransactionRef,
    installmentByTransactionRef: installmentByTransactionRef,
    otherParticipantNamesByTransactionRef: otherParticipantNamesByTransactionRef,
  );
});

/// Default pay-cycle anchor for the People Ledger's Previous/Current Cycle
/// split — the 17th of each month, matching every other cycle anchor in this
/// codebase (`CreditCardProfile.statementDay`'s implicit default, the
/// Dashboard's salary-cycle strategies). Not yet user-configurable anywhere
/// in the app, so every person shares this one constant for now.
const personCycleAnchor = CycleAnchor(anchorDay: 17);

/// The two-section carry-forward view for one person's Contact Ledger:
/// closed, still-unsettled expense-linked entries from before the current
/// cycle ([PersonCycleView.previousCyclePending] — surfaced so they aren't
/// missed once a new cycle starts) and every current-cycle entry
/// ([PersonCycleView.current], always shown regardless of settled state,
/// carried-forward entries first). Built on
/// [CycleEngine.classifyForCarryForward] via [PersonTimelineCycleItem], so
/// this is the only place the People module implements carry-forward —
/// nothing here reimplements [CycleAnchor]/[CycleEngine] math.
///
/// Only [PersonTimelineCategory.assignedExpense]/[PersonTimelineCategory.splitExpense]
/// entries participate — they're the only ones with a real Pending/Partial/
/// Completed lifecycle (backed by an `Installment`). Every other category
/// (manual lending, manual settlements, adjustments, plain references) has
/// no objective "is this outstanding" answer, so those entries are returned
/// separately in [PersonCycleView.uncycled], unaffected by cycle logic, for
/// the caller to render as a flat running-balance list.
typedef PersonCycleView = ({
  List<PersonTimelineEntry> previousCyclePending,
  List<PersonTimelineEntry> current,
  List<PersonTimelineEntry> future,
  Set<String> carriedForwardIds,
  List<PersonTimelineEntry> uncycled,
});

/// Splits a person's timeline into cyclable (assignedExpense/splitExpense)
/// vs uncycled entries and runs the cyclable ones through
/// [CycleEngine.classifyForCarryForward] exactly once — shared by
/// [personCycleViewProvider] and [personCycleSummaryProvider] so both read
/// the same engine invocation instead of each running its own, per the
/// single-source-of-truth rule the shared engine exists to enforce.
({CycleEngineResult<PersonTimelineCycleItem> result, List<PersonTimelineEntry> uncycled}) _classifyPersonTimeline(
  List<PersonTimelineEntry> timeline,
) {
  final cyclable = <PersonTimelineEntry>[];
  final uncycled = <PersonTimelineEntry>[];
  for (final entry in timeline) {
    final isCyclable = entry.category == PersonTimelineCategory.assignedExpense ||
        entry.category == PersonTimelineCategory.splitExpense;
    (isCyclable ? cyclable : uncycled).add(entry);
  }

  final items = cyclable.map(PersonTimelineCycleItem.new).toList();
  final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor);
  return (result: result, uncycled: uncycled);
}

final personCycleViewProvider = Provider.autoDispose.family<PersonCycleView, String>((ref, personId) {
  final timeline = ref.watch(personTimelineProvider(personId));
  final classified = _classifyPersonTimeline(timeline);
  final result = classified.result;

  final previousCyclePending = result.previousCyclePending.map((item) => item.entry).toList();
  final current = [
    ...previousCyclePending,
    ...result.current.map((item) => item.entry),
  ];

  return (
    previousCyclePending: previousCyclePending,
    current: current,
    future: result.future.map((item) => item.entry).toList(),
    carriedForwardIds: previousCyclePending.map((e) => e.id).toSet(),
    uncycled: classified.uncycled,
  );
});

/// The People Dashboard summary for one person — Previous Cycle, Current
/// Cycle, and Overall sections. Built from the same
/// [CycleEngine.classifyForCarryForward] call [personCycleViewProvider]
/// already makes (via `_classifyPersonTimeline`), plus [PersonOverallTotals]
/// over the person's active ledger entries and their cached
/// `Person.currentBalance` — no second carry-forward classification.
final personCycleSummaryProvider = Provider.autoDispose.family<PersonCycleSummary, String>((ref, personId) {
  final timeline = ref.watch(personTimelineProvider(personId));
  final classified = _classifyPersonTimeline(timeline);

  final ledgerEntries = ref.watch(ledgerStreamProvider(personId)).value ?? const [];
  final overallTotals = PersonOverallTotals.from(ledgerEntries);

  final people = ref.watch(peopleStreamProvider).value ?? const [];
  final netBalance = people.where((p) => p.id == personId).firstOrNull?.currentBalance ?? overallTotals.netBalance;

  return PersonCycleSummary.from(
    cycleResult: classified.result,
    overallTotals: overallTotals,
    netBalance: netBalance,
  );
});
