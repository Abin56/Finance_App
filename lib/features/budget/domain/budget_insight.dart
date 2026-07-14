import '../../../core/extensions/num_extensions.dart';

/// Discrete alert state for a budget's usage — exposed so a future
/// notifications milestone can react to crossing a threshold without
/// re-deriving the math itself. This module only computes state; it never
/// sends a notification.
enum BudgetAlertLevel { none, at50, at75, at90, at100, over }

/// Pure spend-vs-limit calculator for a budget over a period (a single day
/// for daily budgets, a calendar month for monthly/category budgets). Takes
/// already-computed `spent`/`limit` values — no Firestore/Riverpod
/// dependency, so this is trivial to unit test in isolation.
class BudgetInsight {
  BudgetInsight({
    required this.limit,
    required this.spent,
    required this.periodStart,
    required this.periodEnd,
    DateTime? now,
  }) : _now = now ?? DateTime.now();

  final double limit;
  final double spent;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime _now;

  double get remaining => limit - spent;

  bool get isOverBudget => remaining < 0;

  /// Spent-of-limit ratio, clamped to a safe 0.0–1.0 range for progress UI.
  double get usageRatio => limit == 0 ? 0 : (spent / limit).clampedProgress;

  /// Raw (unclamped) usage percentage — used for alert-level thresholds so
  /// "150% over" is distinguishable from "100% exactly" upstream if needed.
  double get usageRatioRaw => limit == 0 ? 0 : spent / limit;

  BudgetAlertLevel get alertLevel {
    final ratio = usageRatioRaw;
    if (ratio > 1) return BudgetAlertLevel.over;
    if (ratio >= 1) return BudgetAlertLevel.at100;
    if (ratio >= 0.9) return BudgetAlertLevel.at90;
    if (ratio >= 0.75) return BudgetAlertLevel.at75;
    if (ratio >= 0.5) return BudgetAlertLevel.at50;
    return BudgetAlertLevel.none;
  }

  int get totalDays => periodEnd.difference(periodStart).inDays + 1;

  /// Days elapsed so far in the period, including today — always at least
  /// 1 (even on the period's first day) so average-spend math never
  /// divides by zero.
  int get daysElapsed {
    final elapsed = _now.difference(periodStart).inDays + 1;
    return elapsed.clamp(1, totalDays);
  }

  int get daysRemaining => (totalDays - daysElapsed).clamp(0, totalDays);

  double get averageDailySpend => spent / daysElapsed;

  /// How much can still be spent per remaining day without exceeding the
  /// budget. 0 on the period's last day (nothing left to average over).
  double get averageDailyBudgetRemaining => daysRemaining == 0 ? 0 : remaining / daysRemaining;

  /// Projected total spend for the full period at the current daily pace.
  double get predictedTotalSpend => averageDailySpend * totalDays;

  bool get predictedToExceedBudget => predictedTotalSpend > limit;
}
