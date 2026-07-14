import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
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

/// The active monthly budget's spending, with a month selector so past
/// months' spending can be reviewed against the same ongoing budget
/// amount (the "Previous Month History" requirement) without needing a
/// per-month Firestore document.
class MonthlyBudgetCard extends ConsumerStatefulWidget {
  const MonthlyBudgetCard({super.key});

  @override
  ConsumerState<MonthlyBudgetCard> createState() => _MonthlyBudgetCardState();
}

class _MonthlyBudgetCardState extends ConsumerState<MonthlyBudgetCard> {
  late DateTime _selectedMonth = DateTime.now().startOfMonth;

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final budget = ref.watch(monthlyBudgetProvider);

    if (budget == null) {
      return AppCard(
        onTap: () => BudgetFormSheet.show(context, type: BudgetType.monthly),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, color: context.colors.primary),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text('Set a monthly budget', style: context.textTheme.titleMedium),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }

    final insight = ref.watch(monthlyBudgetInsightProvider(_selectedMonth))!;
    final isCurrentMonth = _selectedMonth.isSameMonth(DateTime.now());

    return AppCard(
      onTap: () => BudgetFormSheet.show(context, type: BudgetType.monthly, budget: budget),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly budget', style: context.textTheme.titleMedium),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    iconSize: AppSizes.iconSm,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _shiftMonth(-1),
                  ),
                  Text(_selectedMonth.monthYear, style: context.textTheme.bodyMedium),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    iconSize: AppSizes.iconSm,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
                  ),
                ],
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
          if (isCurrentMonth && !insight.isOverBudget && insight.daysRemaining > 0) ...[
            const SizedBox(height: AppSizes.xs),
            Text(
              '${CurrencyFormatter.instance.format(insight.averageDailyBudgetRemaining)}/day for the rest of the month',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
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
