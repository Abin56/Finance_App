import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../categories/domain/category.dart';
import '../../../categories/domain/category_type.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/budget_type.dart';
import '../providers/budget_providers.dart';
import 'budget_form_sheet.dart';
import 'category_budget_tile.dart';

/// Section listing every per-category budget, with an "Add category
/// budget" action that only offers expense categories which don't
/// already have an active budget.
class CategoryBudgetsSection extends ConsumerWidget {
  const CategoryBudgetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryBudgets = ref.watch(categoryBudgetsProvider);
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};

    final budgetedCategoryIds = categoryBudgets.map((b) => b.categoryId).toSet();
    final availableCategories = categories
        .where((c) => c.isActive && c.type.appliesTo(TransactionType.expense))
        .where((c) => !budgetedCategoryIds.contains(c.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Category budgets', style: context.textTheme.titleMedium),
            if (availableCategories.isNotEmpty)
              TextButton.icon(
                onPressed: () => _showCategoryPicker(context, availableCategories),
                icon: const Icon(Icons.add_rounded, size: AppSizes.iconSm),
                label: const Text('Add'),
              ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        if (categoryBudgets.isEmpty)
          const EmptyState(
            icon: Icons.pie_chart_outline_rounded,
            title: 'No category budgets',
            subtitle: 'Set limits like Food or Shopping to track spending by category.',
          )
        else
          for (final budget in categoryBudgets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: CategoryBudgetTile(budget: budget, category: categoriesById[budget.categoryId]),
            ),
      ],
    );
  }

  Future<void> _showCategoryPicker(BuildContext context, List<Category> availableCategories) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final category in availableCategories)
              ListTile(
                leading: Icon(category.icon, color: Color(category.colorValue)),
                title: Text(category.name),
                onTap: () => Navigator.of(context).pop(category.id),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;

    final category = availableCategories.firstWhere((c) => c.id == selected);
    await BudgetFormSheet.show(
      context,
      type: BudgetType.monthly,
      categoryId: selected,
      categoryName: category.name,
    );
  }
}
