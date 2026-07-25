import 'package:finance_app/core/payment_schedule/domain/cycle_anchor.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_engine.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_item.dart';
import 'package:finance_app/core/payment_schedule/domain/cycle_source_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic [CycleItem] fake — not a real domain adapter — so this file
/// tests [CycleEngine.classifyForCarryForward] against the [CycleItem]
/// contract directly, independent of any one feature (Credit Cards, People,
/// EMI/Loan). This is the engine's only direct test; every existing adapter
/// test (`person_timeline_cycle_item_test.dart`) exercises the engine only
/// indirectly through its own feature's data.
class _FakeCycleItem extends CycleItem {
  const _FakeCycleItem({
    required this.id,
    required this.cycleDate,
    this.isSettled = false,
    this.carryForwardEligible = true,
  });

  @override
  final String id;

  @override
  final DateTime cycleDate;

  @override
  final bool isSettled;

  @override
  final bool carryForwardEligible;

  @override
  CycleSourceType get sourceType => CycleSourceType.other;

  @override
  String get sourceId => id;

  @override
  double? get totalAmount => null;

  @override
  double? get paidAmount => null;

  @override
  bool get isOverdue => false;
}

void main() {
  const anchor = CycleAnchor(anchorDay: 17);
  final now = DateTime(2026, 7, 22); // current cycle: 18 Jul -> 17 Aug

  group('CycleEngine.classifyForCarryForward', () {
    test('a previous-cycle item that is unsettled carries forward', () {
      final item = _FakeCycleItem(id: 'a', cycleDate: DateTime(2026, 7, 1));

      final result = CycleEngine.classifyForCarryForward([item], anchor, now: now);

      expect(result.previousCyclePending.map((i) => i.id), ['a']);
      expect(result.current, isEmpty);
      expect(result.future, isEmpty);
    });

    test('a previous-cycle item that is settled disappears entirely', () {
      final item = _FakeCycleItem(id: 'a', cycleDate: DateTime(2026, 7, 1), isSettled: true);

      final result = CycleEngine.classifyForCarryForward([item], anchor, now: now);

      expect(result.previousCyclePending, isEmpty);
      expect(result.current, isEmpty);
      expect(result.future, isEmpty);
    });

    test('a previous-cycle item that opts out via carryForwardEligible=false is dropped even if unsettled', () {
      final item = _FakeCycleItem(
        id: 'a',
        cycleDate: DateTime(2026, 7, 1),
        carryForwardEligible: false,
      );

      final result = CycleEngine.classifyForCarryForward([item], anchor, now: now);

      expect(result.previousCyclePending, isEmpty);
    });

    test('a current-cycle item always shows in current, settled or not', () {
      final unsettled = _FakeCycleItem(id: 'a', cycleDate: DateTime(2026, 7, 20));
      final settled = _FakeCycleItem(id: 'b', cycleDate: DateTime(2026, 7, 25), isSettled: true);

      final result = CycleEngine.classifyForCarryForward([unsettled, settled], anchor, now: now);

      expect(result.current.map((i) => i.id).toSet(), {'a', 'b'});
      expect(result.previousCyclePending, isEmpty);
    });

    test('a future-cycle item always shows in future, never in current or previousCyclePending', () {
      final item = _FakeCycleItem(id: 'a', cycleDate: DateTime(2026, 8, 20));

      final result = CycleEngine.classifyForCarryForward([item], anchor, now: now);

      expect(result.future.map((i) => i.id), ['a']);
      expect(result.current, isEmpty);
      expect(result.previousCyclePending, isEmpty);
    });

    test('a mixed list is bucketed correctly and independently per item', () {
      final items = [
        _FakeCycleItem(id: 'prevPending', cycleDate: DateTime(2026, 7, 1)),
        _FakeCycleItem(id: 'prevSettled', cycleDate: DateTime(2026, 7, 5), isSettled: true),
        _FakeCycleItem(id: 'current', cycleDate: DateTime(2026, 7, 20)),
        _FakeCycleItem(id: 'future', cycleDate: DateTime(2026, 8, 20)),
      ];

      final result = CycleEngine.classifyForCarryForward(items, anchor, now: now);

      expect(result.previousCyclePending.map((i) => i.id), ['prevPending']);
      expect(result.current.map((i) => i.id), ['current']);
      expect(result.future.map((i) => i.id), ['future']);
    });

    test('an empty item list produces empty buckets', () {
      final result = CycleEngine.classifyForCarryForward(<_FakeCycleItem>[], anchor, now: now);

      expect(result.previousCyclePending, isEmpty);
      expect(result.current, isEmpty);
      expect(result.future, isEmpty);
    });
  });
}
