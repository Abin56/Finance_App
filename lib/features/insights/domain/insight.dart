/// How favorable an [Insight] is — drives icon/color choice in the
/// presentation layer, never persisted or computed from anything but the
/// rule that produced the insight.
enum InsightSeverity { positive, neutral, warning }

/// Which figure an [Insight] is about — lets a consumer group/filter
/// insights (e.g. Financial Health Indicators only wants [savingsRate],
/// [creditUtilization], [debtTrend], [cashFlowTrend], [spendingTrend]).
enum InsightCategory {
  savings,
  spendingCategory,
  creditUtilization,
  upcomingDue,
  savingsRate,
  debtTrend,
  cashFlowTrend,
  spendingTrend,
}

/// One generated takeaway — a human-readable message plus enough structure
/// for a consumer to style/group it. Built exclusively by functions in
/// `insight_rules.dart` from an [InsightInputs] bag; never constructed
/// ad hoc elsewhere, so every insight in the app traces back to one of
/// those rules.
class Insight {
  const Insight({required this.message, required this.severity, required this.category});

  final String message;
  final InsightSeverity severity;
  final InsightCategory category;
}
