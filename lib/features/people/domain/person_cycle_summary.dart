import '../../../core/payment_schedule/domain/cycle_aggregate.dart';
import '../../../core/payment_schedule/domain/cycle_engine.dart';
import 'person_overall_totals.dart';
import 'person_timeline_cycle_item.dart';

/// The per-person cycle dashboard: Previous Cycle / Current Cycle / Overall,
/// each with the exact fields the People Dashboard needs. Computed once,
/// from the same [CycleEngineResult] `personCycleViewProvider` already
/// produces (via `_classifyPersonTimeline`) plus [CycleAggregate] and
/// [PersonOverallTotals] — no second carry-forward classification, no
/// duplicate sums.
class PersonCycleSummary {
  const PersonCycleSummary({
    required this.previousOutstanding,
    required this.previousCarryForward,
    required this.previousTotalPaid,
    required this.previousRemaining,
    required this.currentTotalSplitExpenses,
    required this.currentTotalPaid,
    required this.currentRemaining,
    required this.totalYouOwe,
    required this.totalTheyOwe,
    required this.netBalance,
  });

  // Previous Cycle
  final double previousOutstanding;
  final double previousCarryForward;
  final double previousTotalPaid;
  final double previousRemaining;

  // Current Cycle
  final double currentTotalSplitExpenses;
  final double currentTotalPaid;
  final double currentRemaining;

  // Overall
  final double totalYouOwe;
  final double totalTheyOwe;
  final double netBalance;

  /// Builds the summary from a [CycleEngineResult] (over
  /// [PersonTimelineCycleItem]s), the person's overall ledger totals, and
  /// their cached net balance. Pure — no I/O, no Riverpod dependency.
  static PersonCycleSummary from({
    required CycleEngineResult<PersonTimelineCycleItem> cycleResult,
    required PersonOverallTotals overallTotals,
    required double netBalance,
  }) {
    final aggregate = CycleAggregate.from(cycleResult);

    double sumPaid(List<PersonTimelineCycleItem> items) =>
        items.fold(0.0, (sum, item) => sum + (item.paidAmount ?? 0));
    double sumTotal(List<PersonTimelineCycleItem> items) =>
        items.fold(0.0, (sum, item) => sum + (item.totalAmount ?? 0));

    return PersonCycleSummary(
      previousOutstanding: aggregate.previousCyclePendingTotal,
      previousCarryForward: aggregate.previousCyclePendingTotal,
      previousTotalPaid: sumPaid(cycleResult.previousCyclePending),
      previousRemaining: aggregate.previousCyclePendingTotal,
      currentTotalSplitExpenses: sumTotal(cycleResult.current),
      currentTotalPaid: sumPaid(cycleResult.current),
      currentRemaining: aggregate.currentTotal,
      totalYouOwe: overallTotals.totalYouOwe,
      totalTheyOwe: overallTotals.totalTheyOwe,
      netBalance: netBalance,
    );
  }
}
