import 'package:finance_app/core/payment_schedule/domain/cycle_aggregate.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_engine.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_item.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_source_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for `CycleAggregate` — the new standalone summary type built on
/// top of `CycleEngineResult`. Built against synthetic `CycleEngineResult`
/// fixtures directly (not run through `CycleEngine.classifyForCarryForward`)
/// since this type only ever consumes an already-classified result; how
/// items got classified is `cycle_engine_test.dart`'s concern, not this
/// file's.
class _FakeCycleItem extends CycleItem {
  const _FakeCycleItem({
    required this.id,
    required this.sourceType,
    this.totalAmount,
    this.paidAmount,
  });

  @override
  final String id;

  @override
  final CycleSourceType sourceType;

  @override
  final double? totalAmount;

  @override
  final double? paidAmount;

  @override
  String get sourceId => id;

  @override
  DateTime get cycleDate => DateTime(2026, 1, 1);

  @override
  bool get isSettled => false;

  @override
  bool get isOverdue => false;
}

void main() {
  group('CycleAggregate.from', () {
    test('sums remainingAmount across previousCyclePending and current separately', () {
      final result = CycleEngineResult<_FakeCycleItem>(
        previousCyclePending: [
          _FakeCycleItem(id: 'a', sourceType: CycleSourceType.bill, totalAmount: 100, paidAmount: 40),
          _FakeCycleItem(id: 'b', sourceType: CycleSourceType.emi, totalAmount: 200, paidAmount: 0),
        ],
        current: [
          _FakeCycleItem(id: 'c', sourceType: CycleSourceType.loan, totalAmount: 50, paidAmount: 50),
        ],
        future: [
          _FakeCycleItem(id: 'd', sourceType: CycleSourceType.bill, totalAmount: 999, paidAmount: 0),
        ],
      );

      final aggregate = CycleAggregate.from(result);

      expect(aggregate.previousCyclePendingTotal, 60 + 200);
      expect(aggregate.currentTotal, 0);
      expect(aggregate.outstandingTotal, 260);
    });

    test('excludes future items from every total and count', () {
      final result = CycleEngineResult<_FakeCycleItem>(
        previousCyclePending: [],
        current: [],
        future: [
          _FakeCycleItem(id: 'a', sourceType: CycleSourceType.bill, totalAmount: 500, paidAmount: 0),
        ],
      );

      final aggregate = CycleAggregate.from(result);

      expect(aggregate.outstandingTotal, 0);
      expect(aggregate.countBySourceType, isEmpty);
    });

    test('items with null totalAmount/paidAmount contribute zero, not an error', () {
      final result = CycleEngineResult<_FakeCycleItem>(
        previousCyclePending: [
          _FakeCycleItem(id: 'a', sourceType: CycleSourceType.manualAdjustment),
        ],
        current: [],
        future: [],
      );

      final aggregate = CycleAggregate.from(result);

      expect(aggregate.previousCyclePendingTotal, 0);
      expect(aggregate.previousCyclePendingCount, 1);
    });

    test('countBySourceType tallies previousCyclePending + current combined, per source type', () {
      final result = CycleEngineResult<_FakeCycleItem>(
        previousCyclePending: [
          _FakeCycleItem(id: 'a', sourceType: CycleSourceType.bill),
          _FakeCycleItem(id: 'b', sourceType: CycleSourceType.bill),
        ],
        current: [
          _FakeCycleItem(id: 'c', sourceType: CycleSourceType.bill),
          _FakeCycleItem(id: 'd', sourceType: CycleSourceType.emi),
        ],
        future: [
          _FakeCycleItem(id: 'e', sourceType: CycleSourceType.bill),
        ],
      );

      final aggregate = CycleAggregate.from(result);

      expect(aggregate.countBySourceType[CycleSourceType.bill], 3);
      expect(aggregate.countBySourceType[CycleSourceType.emi], 1);
      expect(aggregate.countBySourceType[CycleSourceType.loan], isNull);
    });

    test('an empty result produces all-zero totals and counts', () {
      final result = CycleEngineResult<_FakeCycleItem>(previousCyclePending: [], current: [], future: []);

      final aggregate = CycleAggregate.from(result);

      expect(aggregate.previousCyclePendingTotal, 0);
      expect(aggregate.currentTotal, 0);
      expect(aggregate.outstandingTotal, 0);
      expect(aggregate.previousCyclePendingCount, 0);
      expect(aggregate.currentCount, 0);
      expect(aggregate.countBySourceType, isEmpty);
    });
  });
}
