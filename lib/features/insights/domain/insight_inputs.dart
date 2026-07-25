/// Every figure an [Insight] rule is allowed to read — deliberately a flat
/// bag of already-computed values, each one required to be passed in by
/// the caller from an existing provider's output (see
/// `insight_generation_provider.dart` for where each field is sourced).
/// No rule function may derive a NEW figure from raw records; if a rule
/// needs a number this bag doesn't have, that number must be added here by
/// wiring in another existing provider, not computed inline in a rule.
class InsightInputs {
  const InsightInputs({
    required this.income,
    required this.expenses,
    required this.previousIncome,
    required this.previousExpenses,
    this.topCategoryName,
    this.topCategoryAmount,
    this.previousTopCategoryAmount,
    this.creditUtilization,
    this.previousCreditUtilization,
    this.upcomingDueTotal,
    this.totalDebt,
    this.previousTotalDebt,
  });

  /// Current period's real income/expenses (transfers already excluded by
  /// the caller, matching every other Reports/Dashboard figure).
  final double income;
  final double expenses;

  /// The immediately preceding period of the same length, for every
  /// trend/comparison rule below.
  final double previousIncome;
  final double previousExpenses;

  /// This period's single highest-spending category, if any — from
  /// `categorySpendingBreakdownProvider`'s ranked list, entry zero.
  final String? topCategoryName;
  final double? topCategoryAmount;

  /// The same category's amount in the previous period, if it was ranked
  /// then too — null when it wasn't (nothing to compare against).
  final double? previousTopCategoryAmount;

  /// Aggregate outstanding/limit ratio (0..1) across every active credit
  /// card — from `totalCreditCardOutstandingProvider`/
  /// `totalCreditAvailableProvider`, the same figures
  /// `CreditUtilizationWidgetCard` renders.
  final double? creditUtilization;
  final double? previousCreditUtilization;

  /// Total still owed across every kind by cycle end — from
  /// `upcomingDueProvider`, summed by the caller.
  final double? upcomingDueTotal;

  /// Sum of outstanding balances across Credit Cards + EMI + Loans-I-owe
  /// (there is no "loans I owe" figure in this codebase — see
  /// `loans_widget_card.dart` — so this is Credit Card + EMI only today).
  /// Summed by the caller from each feature's own existing outstanding
  /// total; no new calculation happens here or in any rule.
  final double? totalDebt;
  final double? previousTotalDebt;

  double get netSavings => income - expenses;
  double get previousNetSavings => previousIncome - previousExpenses;

  /// (income - expenses) / income, or null when income is zero (no rate is
  /// well-defined with no income to save from).
  double? get savingsRate => income == 0 ? null : netSavings / income;
}
