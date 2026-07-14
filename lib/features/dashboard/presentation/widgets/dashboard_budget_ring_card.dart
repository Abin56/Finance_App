import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/cards/placeholder_card.dart';
import '../../../../shared/widgets/charts/loan_progress_ring.dart';
import '../../../budget/presentation/providers/budget_providers.dart';

/// Circular "% of budget spent" ring for this month's overall budget —
/// mirrors the Figma reference's Budget Overview card, built on the shared
/// [LoanProgressRing] (same ring used for loan/EMI payoff progress) rather
/// than an ad hoc chart, and animated from 0 on first build. Falls back to
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
        onTap: () => context.push(AppRoutes.budget),
      );
    }

    final spent = monthlyBudget != null
        ? ref.watch(monthSpentProvider(DateTime.now()))
        : ref.watch(todaySpentProvider);
    final remaining = budget.amount - spent;
    final progress = budget.amount == 0 ? 0.0 : (spent / budget.amount).clampedProgress;
    final overBudget = remaining < 0;
    final ringColor = progress >= 1 ? AppColors.error : (progress >= 0.8 ? AppColors.warning : AppColors.success);

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.budget),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Budget overview', style: context.textTheme.titleMedium),
                    Text(
                      monthlyBudget != null ? 'This month' : 'Today',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedProgress, _) {
                      return LoanProgressRing(
                        progress: animatedProgress,
                        size: 140,
                        strokeWidth: 14,
                        color: ringColor,
                        centerLabel: animatedProgress.asPercent,
                        centerSubLabel: 'of ${CurrencyFormatter.instance.formatCompact(budget.amount)}',
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RingStat(label: 'Spent', value: spent),
                    _RingStat(
                      label: overBudget ? 'Over' : 'Amount Left',
                      value: remaining.abs(),
                      color: overBudget ? AppColors.error : null,
                      alignEnd: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingStat extends StatelessWidget {
  const _RingStat({required this.label, required this.value, this.color, this.alignEnd = false});

  final String label;
  final double value;
  final Color? color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.55)),
        ),
        Text(
          CurrencyFormatter.instance.format(value),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
