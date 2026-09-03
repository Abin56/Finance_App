import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/cash_flow/presentation/providers/cash_flow_providers.dart';
import '../../../../features/credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../../features/emi/presentation/providers/emi_providers.dart';
import '../../../../features/reports/domain/reports_period.dart';
import '../../../../features/reports/presentation/providers/category_spending_breakdown_provider.dart';
import '../../../../features/transactions/domain/transaction_type.dart';
import '../../../../features/transactions/presentation/providers/transaction_providers.dart';
import '../../domain/insight.dart';
import '../../domain/insight_inputs.dart';
import '../../domain/insight_rules.dart';

/// The two equal-length windows [insightInputsProvider]/
/// [generalInsightsProvider]/[healthIndicatorsProvider] compare — current
/// vs. immediately-preceding period.
typedef InsightPeriod = ({DateRange range, DateRange previousRange, ReportsPeriod period});

/// Builds [InsightInputs] for [args] purely by composing existing
/// providers — [calculableTransactionsProvider] for income/expenses/top
/// category (via [categorySpendingBreakdownProvider]),
/// [totalCreditCardOutstandingProvider]/[totalCreditAvailableProvider] for
/// utilization, [totalDueThisMonthProvider] for the upcoming-due total, and
/// EMI/Credit-Card outstanding for [InsightInputs.totalDebt]. No figure
/// here is computed from raw records that isn't already computed by one of
/// those providers.
final insightInputsProvider = Provider.family<InsightInputs, InsightPeriod>((ref, args) {
  final transactions = ref.watch(calculableTransactionsProvider);

  double totalFor(DateRange range, TransactionType type) => transactions
      .where((t) => type == t.type && range.contains(args.period.reportDateFor(t)))
      .fold(0.0, (sum, t) => sum + t.amount);

  final income = totalFor(args.range, TransactionType.income);
  final expenses = totalFor(args.range, TransactionType.expense);
  final previousIncome = totalFor(args.previousRange, TransactionType.income);
  final previousExpenses = totalFor(args.previousRange, TransactionType.expense);

  final categoryEntries = ref.watch(categorySpendingBreakdownProvider((range: args.range, period: args.period)));
  final previousCategoryEntries =
      ref.watch(categorySpendingBreakdownProvider((range: args.previousRange, period: args.period)));
  final topCategory = categoryEntries.isEmpty ? null : categoryEntries.first;
  final previousTopCategoryAmount = topCategory == null
      ? null
      : previousCategoryEntries.where((e) => e.category.id == topCategory.category.id).firstOrNull?.amount;

  final outstanding = ref.watch(totalCreditCardOutstandingProvider);
  final available = ref.watch(totalCreditAvailableProvider);
  final creditLimit = outstanding + available;
  final creditUtilization = creditLimit <= 0 ? null : (outstanding / creditLimit).clamp(0.0, 1.0);

  final upcomingDueTotal = ref.watch(totalDueThisMonthProvider).remaining;

  // Only Credit Card + EMI have an app-wide "outstanding total" provider
  // today — Loans in this codebase are money owed TO the user, not debt
  // the user owes (see `loans_widget_card.dart`), so they're excluded from
  // a debt total by definition, not by omission.
  final emiOutstanding = ref.watch(totalRemainingEmiBalanceProvider);
  final totalDebt = outstanding + emiOutstanding;

  return InsightInputs(
    income: income,
    expenses: expenses,
    previousIncome: previousIncome,
    previousExpenses: previousExpenses,
    topCategoryName: topCategory?.category.name,
    topCategoryAmount: topCategory?.amount,
    previousTopCategoryAmount: previousTopCategoryAmount,
    creditUtilization: creditUtilization,
    // No historical snapshot of utilization/debt exists anywhere in the
    // app (same limitation as Net Worth's own trend, which is
    // transaction-delta-derived rather than truly historical) — these stay
    // null until such a snapshot mechanism exists; the rules that read
    // them already treat null as "nothing to compare against" rather than
    // zero.
    previousCreditUtilization: null,
    upcomingDueTotal: upcomingDueTotal,
    totalDebt: totalDebt,
    previousTotalDebt: null,
  );
});

/// The "Recent Insights" feed — every [generalInsightRules] result that
/// isn't null, in rule order.
final generalInsightsProvider = Provider.family<List<Insight>, InsightPeriod>((ref, args) {
  final inputs = ref.watch(insightInputsProvider(args));
  return generalInsightRules.map((rule) => rule(inputs)).nonNulls.toList();
});

/// The fixed Financial Health Indicators set — every [healthIndicatorRules]
/// result that isn't null, in rule order.
final healthIndicatorsProvider = Provider.family<List<Insight>, InsightPeriod>((ref, args) {
  final inputs = ref.watch(insightInputsProvider(args));
  return healthIndicatorRules.map((rule) => rule(inputs)).nonNulls.toList();
});
