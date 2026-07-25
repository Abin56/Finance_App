import 'package:finance_app/core/payment_schedule/domain/cycle_engine.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/ledger_entry_type.dart';
import 'package:finance_app/features/people/domain/person_timeline_builder.dart';
import 'package:finance_app/features/people/domain/person_timeline_cycle_item.dart';
import 'package:finance_app/features/people/domain/person_timeline_entry.dart';
import 'package:finance_app/features/people/presentation/providers/person_timeline_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for the People Ledger's Previous/Current Cycle carry-forward —
/// `PersonTimelineCycleItem` (the `CycleItem` adapter) run through the same
/// `CycleEngine.classifyForCarryForward` Credit Cards/EMI already use, with
/// `personCycleAnchor` (day 17). Mirrors the settlement rules from the task:
/// fully settled -> drops out of "previous cycle pending"; partial/pending ->
/// carries forward; only assignedExpense/splitExpense entries participate.
Installment _installment({
  double amountDue = 100,
  double amountPaid = 0,
  DateTime? dueDate,
  bool isSkipped = false,
}) {
  return Installment(
    id: 'inst1',
    scheduleId: 'sched1',
    ownerType: OwnerType.splitExpense,
    ownerId: 'expense1',
    sequenceNumber: 1,
    dueDate: dueDate ?? DateTime(2026, 3, 1),
    amountDue: amountDue,
    amountPaid: amountPaid,
    isSkipped: isSkipped,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  LedgerEntry giveEntry({
    required String id,
    required DateTime date,
    double amount = 100,
    String transactionRef = 'txn1',
  }) {
    return LedgerEntry(
      id: id,
      personId: 'p1',
      type: LedgerEntryType.gave,
      amount: amount,
      date: date,
      note: 'Split: Dinner',
      transactionRef: transactionRef,
      createdAt: date,
    );
  }

  Installment installmentWithStatus(InstallmentStatus status, {double amountDue = 100}) {
    switch (status) {
      case InstallmentStatus.paid:
        return _installment(amountDue: amountDue, amountPaid: amountDue);
      case InstallmentStatus.partiallyPaid:
        return _installment(amountDue: amountDue, amountPaid: amountDue / 2);
      case InstallmentStatus.skipped:
        return _installment(amountDue: amountDue, isSkipped: true);
      case InstallmentStatus.overdue:
        return _installment(amountDue: amountDue, dueDate: DateTime(2000, 1, 1));
      case InstallmentStatus.upcoming:
        return _installment(amountDue: amountDue, dueDate: DateTime(2100, 1, 1));
    }
  }

  List<PersonTimelineEntry> buildCyclable(List<PersonTimelineEntry> all) {
    return all
        .where((e) =>
            e.category == PersonTimelineCategory.assignedExpense || e.category == PersonTimelineCategory.splitExpense)
        .toList();
  }

  group('PersonTimelineCycleItem + CycleEngine.classifyForCarryForward', () {
    test('a previous-cycle entry that is still Pending carries forward', () {
      // "now" is 2026-07-22 (mid current cycle 17 Jul -> 17 Aug); this entry
      // falls in the previous cycle (17 Jun -> 17 Jul).
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry(id: 'l1', date: DateTime(2026, 6, 20))],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
        installmentByTransactionRef: {}, // no installment -> null status, treated as not-settled
      );
      final cyclable = buildCyclable(entries);
      final items = cyclable.map(PersonTimelineCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending.map((i) => i.entry.id), ['l1']);
      expect(result.current, isEmpty);
    });

    test('a previous-cycle entry that is fully settled (Completed) does not carry forward', () {
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry(id: 'l1', date: DateTime(2026, 6, 20))],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
        installmentByTransactionRef: {'txn1': installmentWithStatus(InstallmentStatus.paid)},
      );
      final cyclable = buildCyclable(entries);
      final items = cyclable.map(PersonTimelineCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending, isEmpty);
      expect(result.current, isEmpty);
    });

    test('a previous-cycle entry that is Partial still carries forward', () {
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry(id: 'l1', date: DateTime(2026, 6, 20))],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
        installmentByTransactionRef: {'txn1': installmentWithStatus(InstallmentStatus.partiallyPaid)},
      );
      final cyclable = buildCyclable(entries);
      final items = cyclable.map(PersonTimelineCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending.map((i) => i.entry.id), ['l1']);
    });

    test('a current-cycle entry always shows regardless of settled state', () {
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry(id: 'l1', date: DateTime(2026, 7, 18))],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
        installmentByTransactionRef: {'txn1': installmentWithStatus(InstallmentStatus.paid)},
      );
      final cyclable = buildCyclable(entries);
      final items = cyclable.map(PersonTimelineCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.current.map((i) => i.entry.id), ['l1']);
      expect(result.previousCyclePending, isEmpty);
    });

    test('a soft-deleted previous-cycle entry never appears (excluded before cycle classification)', () {
      final deleted = giveEntry(id: 'l1', date: DateTime(2026, 6, 20))..deletedAt = DateTime(2026, 6, 21);
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [deleted],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
      );

      expect(entries, isEmpty);
    });

    test('lending/adjustment/reference entries are excluded from cycle classification entirely', () {
      final lendingEntry = LedgerEntry(
        id: 'l1',
        personId: 'p1',
        type: LedgerEntryType.gave,
        amount: 50,
        date: DateTime(2026, 6, 1),
        createdAt: DateTime(2026, 6, 1),
      );
      final adjustmentEntry = LedgerEntry(
        id: 'l2',
        personId: 'p1',
        type: LedgerEntryType.adjustment,
        amount: 10,
        date: DateTime(2026, 6, 1),
        createdAt: DateTime(2026, 6, 1),
      );

      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [lendingEntry, adjustmentEntry],
        loans: const [],
      );
      final cyclable = buildCyclable(entries);

      expect(cyclable, isEmpty);
    });

    // Case 1 from the settlement-engine spec: owes $1000, pays $400 ->
    // remaining $600 carries forward; a further $200 paid next cycle ->
    // remaining $400. Regression for the fix to PersonTimelineCycleItem
    // .paidAmount, which used to report a binary isSettled ? total : 0
    // instead of the installment's real amountPaid.
    test('a partially-paid previous-cycle entry carries forward with its real remaining amount, not the full total', () {
      // Owes $1000, pays $400 -> remaining should be $600, not the full $1000.
      final installment = _installment(amountDue: 1000, amountPaid: 400);
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry(id: 'l1', date: DateTime(2026, 6, 20), amount: 1000)],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
        installmentByTransactionRef: {'txn1': installment},
      );
      final cyclable = buildCyclable(entries);
      final items = cyclable.map(PersonTimelineCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending, hasLength(1));
      final carried = result.previousCyclePending.single;
      expect(carried.totalAmount, 1000);
      expect(carried.paidAmount, 400);
      expect(carried.remainingAmount, 600);
    });

    // Case 3: skips several cycles — an installment left unpaid keeps
    // classifying as previousCyclePending on every later "now", with no
    // stored "already carried" state and no mutation of the underlying
    // records across repeated classification passes.
    test('an installment unpaid for several cycles keeps carrying forward on every later now, unmutated', () {
      final installment = _installment(amountDue: 500, amountPaid: 0, dueDate: DateTime(2026, 1, 20));
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry(id: 'l1', date: DateTime(2026, 1, 20), amount: 500)],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
        installmentByTransactionRef: {'txn1': installment},
      );
      final cyclable = buildCyclable(entries);
      final items = cyclable.map(PersonTimelineCycleItem.new).toList();

      final nowValues = [DateTime(2026, 3, 1), DateTime(2026, 5, 1), DateTime(2026, 7, 22)];
      for (final now in nowValues) {
        final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor, now: now);
        expect(result.previousCyclePending.map((i) => i.entry.id), ['l1'], reason: 'now=$now');
      }

      // Classification never mutated the source installment.
      expect(installment.amountPaid, 0);
      expect(installment.amountDue, 500);
    });

    test('a future-cycle entry is surfaced separately and never in current/previousCyclePending', () {
      final entries = PersonTimelineBuilder.build(
        ledgerEntries: [giveEntry(id: 'l1', date: DateTime(2026, 9, 1))],
        loans: const [],
        participantCountByTransactionRef: {'txn1': 1},
        installmentByTransactionRef: {'txn1': installmentWithStatus(InstallmentStatus.upcoming)},
      );
      final cyclable = buildCyclable(entries);
      final items = cyclable.map(PersonTimelineCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, personCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.future.map((i) => i.entry.id), ['l1']);
      expect(result.current, isEmpty);
      expect(result.previousCyclePending, isEmpty);
    });
  });
}
