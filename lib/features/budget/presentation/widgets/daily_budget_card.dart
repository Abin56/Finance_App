import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/animations/count_up_text.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../domain/budget_insight.dart';
import '../../domain/budget_type.dart';
import '../providers/budget_insight_providers.dart';
import '../providers/budget_providers.dart';
import 'budget_alert_badge.dart';
import 'budget_form_sheet.dart';

/// Today's spending against the active daily budget (if any). Tapping
/// when no budget exists opens [BudgetFormSheet] to create one.
class DailyBudgetCard extends ConsumerWidget {
  const DailyBudgetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(dailyBudgetProvider);

    if (budget == null) {
      return AppCard(
        onTap: () => BudgetFormSheet.show(context, type: BudgetType.daily),
        child: Row(
          children: [
            Icon(Icons.today_outlined, color: context.colors.primary),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text('Set a daily budget', style: context.textTheme.titleMedium),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }

    final insight = ref.watch(dailyBudgetInsightProvider)!;

    return AppCard(
      onTap: () => BudgetFormSheet.show(context, type: BudgetType.daily, budget: budget),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Daily budget', style: context.textTheme.titleMedium),
              Text(
                CurrencyFormatter.instance.format(budget.amount),
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          CountUpText(
            value: insight.remaining.abs(),
            formatter: (v) =>
                '${insight.isOverBudget ? '-' : ''}${CurrencyFormatter.instance.format(v)} ${insight.isOverBudget ? 'over' : 'left'}',
            style: context.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: insight.isOverBudget ? AppColors.error : null,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          ProgressBar(progress: insight.usageRatio),
          if (insight.alertLevel != BudgetAlertLevel.none) ...[
            const SizedBox(height: AppSizes.sm),
            BudgetAlertBadge(level: insight.alertLevel),
          ],
        ],
      ),
    );
  }
}
