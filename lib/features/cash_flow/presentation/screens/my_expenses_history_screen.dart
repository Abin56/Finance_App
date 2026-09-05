import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/theme/clay_theme.dart';
import '../../../../core/theme/clay_widgets.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../reports/domain/reports_period.dart';
import '../../domain/cash_flow_period.dart';
import '../providers/cash_flow_providers.dart';
import 'my_expenses_category_screen.dart';

/// "My Expenses" drill-down, level 1 — categories for the selected
/// [cashFlowDateRangeProvider] range. Reads [myExpensesByCategoryProvider]
/// directly (never a separate total) so this screen's footer total is
/// mathematically guaranteed to equal [MyExpensesCard]'s figure — both fold
/// the same [myExpenseLinesForRangeProvider] list.
class MyExpensesHistoryScreen extends ConsumerWidget {
  const MyExpensesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(cashFlowDateRangeProvider);
    final range = ref.watch(resolvedCashFlowRangeProvider);
    final categories = ref.watch(myExpensesByCategoryProvider);
    final total = categories.fold(0.0, (sum, c) => sum + c.amount);

    return Scaffold(
      backgroundColor: AppClay.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppClay.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          'My Expenses',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.md),
              child: ClayCard(
                padding: const EdgeInsets.all(AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rangeLabel(period, range),
                      style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      CurrencyFormatter.instance.format(total),
                      style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_outline_rounded,
                      title: 'No personal expenses',
                      subtitle: 'No expenses found for this period.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(AppSizes.lg, 0, AppSizes.lg, AppSizes.fabClearance),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        return _CategoryTile(
                          categoryId: category.categoryId,
                          label: category.categoryLabel,
                          amount: category.amount,
                        );
                      },
                    ),
            ),
            if (categories.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border(top: BorderSide(color: context.colors.outlineVariant)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      CurrencyFormatter.instance.format(total),
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _rangeLabel(CashFlowPeriod period, DateRange range) {
    if (period.preset != CashFlowPreset.custom) return period.preset.label;
    return '${range.start.shortDate} – ${range.end.shortDate}';
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.categoryId, required this.label, required this.amount});

  final String categoryId;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyExpensesCategoryScreen(categoryId: categoryId, categoryLabel: label),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(
                CurrencyFormatter.instance.format(amount),
                style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: AppSizes.xs),
              Icon(Icons.chevron_right_rounded, size: AppSizes.iconSm, color: context.colors.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
