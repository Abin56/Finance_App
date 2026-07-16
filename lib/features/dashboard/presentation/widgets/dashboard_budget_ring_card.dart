import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../budget/presentation/providers/budget_providers.dart';
import 'dashboard_section_card.dart';

/// Compact "% of budget spent" readout for this month's overall budget —
/// a de-emphasized preview now that Budget Progress sits lower in the
/// Dashboard's priority order. The full ring visualization lives on the
/// Budget screen itself (`MonthlyBudgetCard`/`DailyBudgetCard`); a 5-second
/// glance only needs the bar and the two headline numbers. Falls back to
/// the daily budget when no monthly budget is set, and to an empty state
/// when neither exists.
class DashboardBudgetRingCard extends ConsumerWidget {
  const DashboardBudgetRingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthlyBudget = ref.watch(monthlyBudgetProvider);
    final dailyBudget = ref.watch(dailyBudgetProvider);
    final budget = monthlyBudget ?? dailyBudget;

    if (budget == null) {
      return PlaceholderCard(
        icon: Icons.donut_large_rounded,
        title: 'Budget overview',
        message: 'Set a budget to track your spending here.',
        radius: AppSizes.radiusCard,
        actionLabel: 'Set a budget',
        onTap: () => context.push(AppRoutes.budget),
      );
    }

    final spent = monthlyBudget != null
        ? ref.watch(monthSpentProvider(DateTime.now()))
        : ref.watch(todaySpentProvider);
    final remaining = budget.amount - spent;
    final progress = budget.amount == 0 ? 0.0 : (spent / budget.amount).clampedProgress;
    final overBudget = remaining < 0;

    return DashboardSectionCard(
      child: InkWell(
        onTap: () => context.push(AppRoutes.budget),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Budget overview', style: context.textTheme.titleMedium),
                Text(
                  monthlyBudget != null ? 'This month' : 'Today',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.55)),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            ProgressBar(progress: progress, height: 10),
            const SizedBox(height: AppSizes.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${CurrencyFormatter.instance.format(spent)} spent of ${CurrencyFormatter.instance.formatCompact(budget.amount)}',
                  style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                ),
                Text(
                  overBudget
                      ? '${CurrencyFormatter.instance.format(remaining.abs())} over'
                      : '${CurrencyFormatter.instance.format(remaining)} left',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: overBudget ? AppColors.error : context.colors.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
