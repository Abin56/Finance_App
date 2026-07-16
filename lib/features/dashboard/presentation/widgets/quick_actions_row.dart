import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../expense/presentation/widgets/split_expense_form_sheet.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/screens/add_expense_screen.dart';
import 'more_actions_sheet.dart';

/// Minimum taps to the most common actions — mirrors the Figma dashboard's
/// Add Expense / Add Income / Share Expense / Reports / More. Horizontally
/// scrollable with fixed-width tiles so it never overflows on narrow
/// phones, per the redesign's "scrollable if needed" allowance.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _QuickAction(
            icon: Icons.remove_circle_outline_rounded,
            label: 'Add Expense',
            color: AppColors.expense,
            onTap: () => AddExpenseScreen.show(context, initialType: TransactionType.expense),
          ),
          const SizedBox(width: AppSizes.sm),
          _QuickAction(
            icon: Icons.add_circle_outline_rounded,
            label: 'Add Income',
            color: AppColors.income,
            onTap: () => AddExpenseScreen.show(context, initialType: TransactionType.income),
          ),
          const SizedBox(width: AppSizes.sm),
          _QuickAction(
            icon: Icons.call_split_rounded,
            label: 'Share Expense',
            color: context.colors.primary,
            onTap: () => SplitExpenseFormSheet.show(context),
          ),
          const SizedBox(width: AppSizes.sm),
          _QuickAction(
            icon: Icons.bar_chart_rounded,
            label: 'Reports',
            color: AppColors.pending,
            onTap: () => context.push(AppRoutes.reports),
          ),
          const SizedBox(width: AppSizes.sm),
          _QuickAction(
            icon: Icons.more_horiz_rounded,
            label: 'More',
            color: context.colors.onSurface.withValues(alpha: 0.7),
            onTap: () => MoreActionsSheet.show(context),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          boxShadow: AppShadows.soft(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSizes.md, horizontal: AppSizes.xs),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    label,
                    style: context.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
