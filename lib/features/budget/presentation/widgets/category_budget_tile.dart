import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/charts/progress_bar.dart';
import '../../../categories/domain/category.dart';
import '../../domain/budget.dart';
import '../../domain/budget_insight.dart';
import '../providers/budget_insight_providers.dart';
import 'budget_alert_badge.dart';
import 'budget_form_sheet.dart';

/// One row for a per-category budget — icon/color from the linked
/// [Category], spent/remaining/percentage against it. Swipeable to
/// soft-delete like every other list row in the app.
class CategoryBudgetTile extends ConsumerWidget {
  const CategoryBudgetTile({super.key, required this.budget, required this.category});

  final Budget budget;
  final Category? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(categoryBudgetInsightProvider(budget));
    final color = category != null ? Color(category!.colorValue) : context.colors.primary;

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => BudgetFormSheet.show(
          context,
          type: budget.type,
          categoryId: budget.categoryId,
          categoryName: category?.name,
          budget: budget,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: Icon(category?.icon ?? Icons.category_outlined, color: color, size: AppSizes.iconSm),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Text(category?.name ?? 'Uncategorized', style: context.textTheme.titleMedium),
                  ),
                  Text(
                    '${CurrencyFormatter.instance.format(insight.spent)} / ${CurrencyFormatter.instance.format(budget.amount)}',
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: insight.isOverBudget
                          ? AppColors.error
                          : context.colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.sm),
              ProgressBar(progress: insight.usageRatio),
              if (insight.alertLevel != BudgetAlertLevel.none) ...[
                const SizedBox(height: AppSizes.xs),
                BudgetAlertBadge(level: insight.alertLevel),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
