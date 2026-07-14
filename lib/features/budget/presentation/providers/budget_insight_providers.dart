import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../domain/budget.dart';
import '../../domain/budget_insight.dart';
import 'budget_providers.dart';

/// [BudgetInsight] for the active daily budget, if one exists. Period is
/// just today — daily budgets have no multi-day pacing to project.
final dailyBudgetInsightProvider = Provider<BudgetInsight?>((ref) {
  final budget = ref.watch(dailyBudgetProvider);
  if (budget == null) return null;

  final today = DateTime.now().dateOnly;
  return BudgetInsight(
    limit: budget.amount,
    spent: ref.watch(todaySpentProvider),
    periodStart: today,
    periodEnd: today,
  );
});

/// [BudgetInsight] for the active monthly budget over [month], if one
/// exists. Powers the month-selector history view in [MonthlyBudgetCard]
/// — each selected month gets its own insight against the same ongoing
/// budget amount.
final monthlyBudgetInsightProvider = Provider.family<BudgetInsight?, DateTime>((ref, month) {
  final budget = ref.watch(monthlyBudgetProvider);
  if (budget == null) return null;

  return BudgetInsight(
    limit: budget.amount,
    spent: ref.watch(monthSpentProvider(month)),
    periodStart: month.startOfMonth,
    periodEnd: month.endOfMonth,
  );
});

/// [BudgetInsight] for a single category budget over the current month.
final categoryBudgetInsightProvider = Provider.family<BudgetInsight, Budget>((ref, budget) {
  final now = DateTime.now();
  return BudgetInsight(
    limit: budget.amount,
    spent: ref.watch(categorySpentProvider(budget.categoryId!)),
    periodStart: now.startOfMonth,
    periodEnd: now.endOfMonth,
  );
});
