import '../../../features/reports/domain/reports_period.dart';
import 'financial_view_module.dart';

/// The resolved output of a Financial View widget for one
/// (module, date range) pair — everything the widget needs to render,
/// computed once and safe to cache since it's immutable.
class FinancialViewResult {
  const FinancialViewResult({
    required this.module,
    required this.range,
    required this.amount,
    required this.previousAmount,
    required this.breakdown,
  });

  final FinancialViewModule module;
  final DateRange range;

  /// Total for [module] within [range].
  final double amount;

  /// The same [module]'s total for the equal-length window immediately
  /// preceding [range] — the "vs last cycle" comparison. Null when the
  /// strategy has no natural "previous" window (e.g. a one-off custom range).
  final double? previousAmount;

  /// Sub-totals shown under the headline amount — e.g. for
  /// [FinancialViewModule.combinedExpenses]: My Expenses, Shared, Bills,
  /// EMIs, Loans, Credit Card Payments. Empty for modules with nothing to
  /// break down further (Income, Transfers, Net Cash Flow).
  final Map<String, double> breakdown;

  /// Percent change vs [previousAmount], or null when there's no previous
  /// window or it was zero (nothing to meaningfully compare against).
  double? get percentChange {
    if (previousAmount == null || previousAmount == 0) return null;
    return (amount - previousAmount!) / previousAmount! * 100;
  }
}
