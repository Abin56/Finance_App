import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../widgets/category_budgets_section.dart';
import '../widgets/daily_budget_card.dart';
import '../widgets/monthly_budget_card.dart';
import 'budget_trash_screen.dart';

/// Daily budget, monthly budget (with month selector), and per-category
/// budgets in one screen — everything reachable without a drill-down,
/// consistent with how Accounts/Categories keep list + management on one
/// screen.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BudgetTrashScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: const [
          DailyBudgetCard(),
          SizedBox(height: AppSizes.lg),
          MonthlyBudgetCard(),
          SizedBox(height: AppSizes.xl),
          CategoryBudgetsSection(),
        ],
      ),
    );
  }
}
