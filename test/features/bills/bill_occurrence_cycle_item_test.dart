import 'package:finance_app/core/payment_schedule/domain/cycle_engine.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence_cycle_item.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_occurrence_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for `BillOccurrenceCycleItem` — the `CycleItem` adapter for the
/// occurrence-per-cycle model, replacing the now-removed `BillCycleItem`
/// (which wrapped the whole mutable `Bill` and could never represent a
/// genuinely distinct previous occurrence). Also covers
/// `CycleEngine.classifyForCarryForward` against real occurrences, the case
/// the old adapter's own doc comment said it could not represent.
void main() {
  BillOccurrence occurrence({
    String id = 'o1',
    double amount = 1000,
    double amountPaid = 0,
    bool isSkipped = false,
    required DateTime dueDate,
  }) {
    return BillOccurrence(
      id: id,
      billId: 'b1',
      dueDate: dueDate,
      amount: amount,
      amountPaid: amountPaid,
      isSkipped: isSkipped,
      createdAt: dueDate,
    );
  }

  group('BillOccurrenceCycleItem', () {
    test('isSettled is true once fully paid', () {
      final item = BillOccurrenceCycleItem(
        occurrence(amount: 1000, amountPaid: 1000, dueDate: DateTime(2026, 6, 20)),
      );
      expect(item.isSettled, isTrue);
    });

    test('isSettled is true when skipped, even unpaid', () {
      final item = BillOccurrenceCycleItem(
        occurrence(amount: 1000, amountPaid: 0, isSkipped: true, dueDate: DateTime(2026, 6, 20)),
      );
      expect(item.isSettled, isTrue);
    });

    test('isSettled is false for a partial payment', () {
      final item = BillOccurrenceCycleItem(
        occurrence(amount: 1000, amountPaid: 400, dueDate: DateTime(2026, 6, 20)),
      );
      expect(item.isSettled, isFalse);
    });

    test('isOverdue matches BillOccurrence.status == overdue', () {
      final item = BillOccurrenceCycleItem(
        occurrence(amount: 1000, amountPaid: 0, dueDate: DateTime(2020, 1, 1)),
      );
      expect(item.isOverdue, isTrue);
    });

    test('cycleDate is the occurrence\'s dueDate', () {
      final dueDate = DateTime(2026, 7, 17);
      final item = BillOccurrenceCycleItem(occurrence(dueDate: dueDate));
      expect(item.cycleDate, dueDate);
    });

    test('sourceId points back at the owning bill, not the occurrence itself', () {
      final item = BillOccurrenceCycleItem(occurrence(dueDate: DateTime(2026, 7, 17)));
      expect(item.sourceId, 'b1');
      expect(item.id, 'o1');
    });

    test('carryForwardEligible defaults to true', () {
      final item = BillOccurrenceCycleItem(occurrence(dueDate: DateTime(2026, 7, 17)));
      expect(item.carryForwardEligible, isTrue);
    });
  });

  group('BillOccurrenceCycleItem + CycleEngine.classifyForCarryForward', () {
    test('an unpaid previous-cycle occurrence carries forward — the case the old adapter could not represent', () {
      // "now" is 2026-07-22, mid current cycle (17 Jul -> 17 Aug); this
      // occurrence's due date falls in the previous cycle (17 Jun -> 17 Jul)
      // and is a genuinely separate document from any current occurrence.
      final previous = occurrence(id: 'prev', dueDate: DateTime(2026, 6, 20), amountPaid: 0);
      final items = [previous].map(BillOccurrenceCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, billCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending.map((i) => i.occurrence.id), ['prev']);
      expect(result.current, isEmpty);
    });

    test('a fully paid previous-cycle occurrence does not carry forward', () {
      final previous = occurrence(id: 'prev', dueDate: DateTime(2026, 6, 20), amountPaid: 1000);
      final items = [previous].map(BillOccurrenceCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, billCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending, isEmpty);
    });

    test('a partially paid previous-cycle occurrence still carries forward', () {
      final previous = occurrence(id: 'prev', dueDate: DateTime(2026, 6, 20), amountPaid: 400);
      final items = [previous].map(BillOccurrenceCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, billCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending.map((i) => i.occurrence.id), ['prev']);
    });

    test('a current-cycle occurrence always shows regardless of settled state', () {
      final current = occurrence(id: 'curr', dueDate: DateTime(2026, 7, 18), amountPaid: 1000);
      final items = [current].map(BillOccurrenceCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, billCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.current.map((i) => i.occurrence.id), ['curr']);
      expect(result.previousCyclePending, isEmpty);
    });

    test('a genuinely distinct previous occurrence and current occurrence coexist independently', () {
      // Both are real, separate BillOccurrence documents — the exact
      // scenario the old single-document Bill model could never represent.
      final previous = occurrence(id: 'prev', dueDate: DateTime(2026, 6, 20), amountPaid: 0);
      final current = occurrence(id: 'curr', dueDate: DateTime(2026, 7, 18), amountPaid: 0);
      final items = [previous, current].map(BillOccurrenceCycleItem.new).toList();

      final result = CycleEngine.classifyForCarryForward(items, billCycleAnchor, now: DateTime(2026, 7, 22));

      expect(result.previousCyclePending.map((i) => i.occurrence.id), ['prev']);
      expect(result.current.map((i) => i.occurrence.id), ['curr']);
    });
  });
}
