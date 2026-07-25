import 'cycle_engine.dart';
import 'cycle_item.dart';
import 'cycle_source_type.dart';

/// A summary computed over a [CycleEngineResult] — total outstanding
/// amount, section totals, and a per-[CycleSourceType] breakdown. Exists
/// because [CycleEngine] deliberately returns only raw `List<T>` sections
/// (see its own doc comment: aggregation is a caller's job, not the
/// engine's) — as more features adopt the engine, "total still owed across
/// previousCyclePending + current" becomes a generically useful,
/// feature-agnostic computation worth writing once rather than letting each
/// new adopter (EMI, Loan, Bill, and eventually a cross-feature view) write
/// its own sum loop.
///
/// Pure, no I/O — derives everything from [CycleItem.remainingAmount] and
/// [CycleItem.sourceType], which every adapter already exposes; no new
/// requirement is placed on adapters to use this.
///
/// Deliberately NOT wired into `statementCycleViewProvider`,
/// `personCycleViewProvider`, `emiCycleViewProvider`, or
/// `loanCycleViewProvider`'s existing return shapes — those already do
/// their own inline unwrap/sum and changing their return shape is a
/// separate, deliberate decision for whoever consumes this next, not a side
/// effect of this type's introduction.
class CycleAggregate {
  const CycleAggregate({
    required this.previousCyclePendingTotal,
    required this.currentTotal,
    required this.outstandingTotal,
    required this.previousCyclePendingCount,
    required this.currentCount,
    required this.countBySourceType,
  });

  /// Sum of [CycleItem.remainingAmount] across
  /// [CycleEngineResult.previousCyclePending]. Items with a null
  /// `remainingAmount` (a source that doesn't track a due amount) don't
  /// contribute to this sum.
  final double previousCyclePendingTotal;

  /// Sum of [CycleItem.remainingAmount] across [CycleEngineResult.current].
  final double currentTotal;

  /// [previousCyclePendingTotal] + [currentTotal] — the total still owed
  /// across every item this view surfaces as needing attention. Deliberately
  /// excludes [CycleEngineResult.future] — a future item isn't outstanding
  /// yet, by the same logic the engine itself never shows future items
  /// alongside current ones.
  final double outstandingTotal;

  final int previousCyclePendingCount;
  final int currentCount;

  /// Item count per [CycleSourceType], across [CycleEngineResult.previousCyclePending]
  /// and [CycleEngineResult.current] combined (not [CycleEngineResult.future]) —
  /// e.g. "3 credit card statements, 2 EMI installments still outstanding".
  final Map<CycleSourceType, int> countBySourceType;

  /// Computes a [CycleAggregate] from a [CycleEngineResult]. A feature calls
  /// this after [CycleEngine.classifyForCarryForward] the same way it would
  /// call `.map()` on the result's lists today — one extra, optional step,
  /// not a replacement for reading the raw lists.
  static CycleAggregate from<T extends CycleItem>(CycleEngineResult<T> result) {
    double sumRemaining(List<T> items) =>
        items.fold(0.0, (sum, item) => sum + (item.remainingAmount ?? 0));

    final countBySourceType = <CycleSourceType, int>{};
    for (final item in [...result.previousCyclePending, ...result.current]) {
      countBySourceType[item.sourceType] = (countBySourceType[item.sourceType] ?? 0) + 1;
    }

    final previousTotal = sumRemaining(result.previousCyclePending);
    final currentTotal = sumRemaining(result.current);

    return CycleAggregate(
      previousCyclePendingTotal: previousTotal,
      currentTotal: currentTotal,
      outstandingTotal: previousTotal + currentTotal,
      previousCyclePendingCount: result.previousCyclePending.length,
      currentCount: result.current.length,
      countBySourceType: countBySourceType,
    );
  }
}
