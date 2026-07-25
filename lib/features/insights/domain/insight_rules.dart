import 'insight.dart';
import 'insight_inputs.dart';

/// One pattern-match/threshold check over [InsightInputs] → an [Insight],
/// or null when this rule has nothing to say for the given inputs (e.g. no
/// previous-period data to compare against). Every rule is pure and
/// side-effect free — no rule reads a provider itself, only the bag it's
/// given.
typedef InsightRule = Insight? Function(InsightInputs inputs);

/// Net savings vs the previous period — generalizes the single hardcoded
/// string `ReportsScreen` used to show inline.
Insight? netSavingsTrendRule(InsightInputs inputs) {
  if (inputs.previousNetSavings == 0) return null;
  final delta = inputs.netSavings - inputs.previousNetSavings;
  if (delta == 0) return null;
  final improved = delta > 0;
  return Insight(
    message: improved
        ? 'You saved ${delta.abs().toStringAsFixed(0)} more than the previous period.'
        : 'You saved ${delta.abs().toStringAsFixed(0)} less than the previous period.',
    severity: improved ? InsightSeverity.positive : InsightSeverity.warning,
    category: InsightCategory.savings,
  );
}

/// The single highest-spending category this period, vs. the same
/// category's previous-period amount.
Insight? topSpendingCategoryRule(InsightInputs inputs) {
  final name = inputs.topCategoryName;
  final amount = inputs.topCategoryAmount;
  if (name == null || amount == null || amount <= 0) return null;

  final previous = inputs.previousTopCategoryAmount;
  if (previous == null || previous == 0) {
    return Insight(
      message: 'Your top spending category this period was $name.',
      severity: InsightSeverity.neutral,
      category: InsightCategory.spendingCategory,
    );
  }

  final percentChange = (amount - previous) / previous * 100;
  if (percentChange.abs() < 1) return null;
  final increased = percentChange > 0;
  return Insight(
    message: increased
        ? 'Your spending on $name increased by ${percentChange.abs().toStringAsFixed(0)}% compared to last period.'
        : 'Your spending on $name decreased by ${percentChange.abs().toStringAsFixed(0)}% compared to last period.',
    severity: increased ? InsightSeverity.warning : InsightSeverity.positive,
    category: InsightCategory.spendingCategory,
  );
}

/// Credit utilization crossing a comfort threshold, or trending up/down.
Insight? creditUtilizationRule(InsightInputs inputs) {
  final utilization = inputs.creditUtilization;
  if (utilization == null) return null;

  if (utilization >= 0.75) {
    return Insight(
      message: 'You\'re using ${(utilization * 100).round()}% of your credit limit — consider paying it down.',
      severity: InsightSeverity.warning,
      category: InsightCategory.creditUtilization,
    );
  }

  final previous = inputs.previousCreditUtilization;
  if (previous == null || previous == 0) return null;
  final delta = utilization - previous;
  if (delta.abs() < 0.02) return null;
  final decreased = delta < 0;
  return Insight(
    message: decreased ? 'Your credit utilization decreased.' : 'Your credit utilization increased.',
    severity: decreased ? InsightSeverity.positive : InsightSeverity.warning,
    category: InsightCategory.creditUtilization,
  );
}

/// How much is still due by the current cycle's end, when that total is
/// meaningfully large relative to income.
Insight? upcomingDueRule(InsightInputs inputs) {
  final due = inputs.upcomingDueTotal;
  if (due == null || due <= 0 || inputs.income <= 0) return null;
  final ratio = due / inputs.income;
  if (ratio < 0.5) return null;
  return Insight(
    message: 'You still have ${due.toStringAsFixed(0)} due this cycle.',
    severity: InsightSeverity.neutral,
    category: InsightCategory.upcomingDue,
  );
}

/// Threshold label for savings rate — the "Savings Rate" Financial Health
/// Indicator.
Insight? savingsRateIndicatorRule(InsightInputs inputs) {
  final rate = inputs.savingsRate;
  if (rate == null) return null;
  final percent = (rate * 100).round();
  if (rate >= 0.2) {
    return Insight(
      message: 'Savings Rate: Good ($percent%)',
      severity: InsightSeverity.positive,
      category: InsightCategory.savingsRate,
    );
  }
  if (rate >= 0) {
    return Insight(
      message: 'Savings Rate: Fair ($percent%)',
      severity: InsightSeverity.neutral,
      category: InsightCategory.savingsRate,
    );
  }
  return Insight(
    message: 'Savings Rate: Poor ($percent%)',
    severity: InsightSeverity.warning,
    category: InsightCategory.savingsRate,
  );
}

/// Threshold label for credit utilization — the "Credit Utilization"
/// Financial Health Indicator (distinct from [creditUtilizationRule]'s
/// prose insight; this is the fixed Good/Fair/Poor badge form).
Insight? creditUtilizationIndicatorRule(InsightInputs inputs) {
  final utilization = inputs.creditUtilization;
  if (utilization == null) return null;
  final percent = (utilization * 100).round();
  if (utilization < 0.3) {
    return Insight(
      message: 'Credit Utilization: Good ($percent%)',
      severity: InsightSeverity.positive,
      category: InsightCategory.creditUtilization,
    );
  }
  if (utilization < 0.75) {
    return Insight(
      message: 'Credit Utilization: Fair ($percent%)',
      severity: InsightSeverity.neutral,
      category: InsightCategory.creditUtilization,
    );
  }
  return Insight(
    message: 'Credit Utilization: Poor ($percent%)',
    severity: InsightSeverity.warning,
    category: InsightCategory.creditUtilization,
  );
}

/// Debt trend indicator — total outstanding debt vs the previous period.
Insight? debtTrendIndicatorRule(InsightInputs inputs) {
  final debt = inputs.totalDebt;
  final previous = inputs.previousTotalDebt;
  if (debt == null || previous == null || previous == 0) return null;
  final percentChange = (debt - previous) / previous * 100;
  if (percentChange.abs() < 1) {
    return const Insight(
      message: 'Debt Trend: Stable',
      severity: InsightSeverity.neutral,
      category: InsightCategory.debtTrend,
    );
  }
  final reduced = percentChange < 0;
  return Insight(
    message: reduced
        ? 'Debt Trend: Reducing (${percentChange.abs().toStringAsFixed(0)}% less than last period)'
        : 'Debt Trend: Increasing (${percentChange.abs().toStringAsFixed(0)}% more than last period)',
    severity: reduced ? InsightSeverity.positive : InsightSeverity.warning,
    category: InsightCategory.debtTrend,
  );
}

/// Cash flow trend indicator — net cash flow (income - expenses) direction
/// vs the previous period.
Insight? cashFlowTrendIndicatorRule(InsightInputs inputs) {
  if (inputs.previousNetSavings == 0) return null;
  final delta = inputs.netSavings - inputs.previousNetSavings;
  if (delta == 0) {
    return const Insight(
      message: 'Cash Flow Trend: Stable',
      severity: InsightSeverity.neutral,
      category: InsightCategory.cashFlowTrend,
    );
  }
  final improved = delta > 0;
  return Insight(
    message: improved ? 'Cash Flow Trend: Improving' : 'Cash Flow Trend: Declining',
    severity: improved ? InsightSeverity.positive : InsightSeverity.warning,
    category: InsightCategory.cashFlowTrend,
  );
}

/// Spending trend indicator — total expenses vs the previous period.
Insight? spendingTrendIndicatorRule(InsightInputs inputs) {
  if (inputs.previousExpenses == 0) return null;
  final percentChange = (inputs.expenses - inputs.previousExpenses) / inputs.previousExpenses * 100;
  if (percentChange.abs() < 1) {
    return const Insight(
      message: 'Spending Trend: Stable',
      severity: InsightSeverity.neutral,
      category: InsightCategory.spendingTrend,
    );
  }
  final increased = percentChange > 0;
  return Insight(
    message: increased
        ? 'Spending Trend: Up ${percentChange.abs().toStringAsFixed(0)}% vs last period'
        : 'Spending Trend: Down ${percentChange.abs().toStringAsFixed(0)}% vs last period',
    severity: increased ? InsightSeverity.warning : InsightSeverity.positive,
    category: InsightCategory.spendingTrend,
  );
}

/// Every general-purpose insight rule, in priority order — the "Recent
/// Insights" feed.
const List<InsightRule> generalInsightRules = [
  netSavingsTrendRule,
  creditUtilizationRule,
  topSpendingCategoryRule,
  upcomingDueRule,
];

/// Every Financial Health Indicator rule, in display order — a fixed set
/// of Good/Fair/Poor-style badges rather than a variable-length feed.
const List<InsightRule> healthIndicatorRules = [
  savingsRateIndicatorRule,
  creditUtilizationIndicatorRule,
  debtTrendIndicatorRule,
  cashFlowTrendIndicatorRule,
  spendingTrendIndicatorRule,
];
