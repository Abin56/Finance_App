import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_shadows.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';

/// This month's Income / Expense / Savings at a glance — three equal
/// premium cards replacing the old flat stat row, per the Dashboard
/// redesign's "Monthly Summary" spec.
class DashboardMonthlySummaryCards extends StatelessWidget {
  const DashboardMonthlySummaryCards({super.key, required this.income, required this.expenses});

  final double income;
  final double expenses;

  @override
  Widget build(BuildContext context) {
    final net = income - expenses;
    return Row(
      // At larger text scales a wrapped label makes one card taller than the
      // others; without this the shorter cards centre and float out of line.
      // (Not `stretch` — this Row sits in a scroll view, so its vertical
      // extent is unbounded and stretch would assert.)
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.arrow_downward_rounded,
            label: 'Income',
            value: income,
            color: AppColors.income,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _SummaryCard(
            icon: Icons.arrow_upward_rounded,
            label: 'Expense',
            value: expenses,
            color: AppColors.expense,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: _SummaryCard(
            icon: Icons.savings_rounded,
            label: 'Savings',
            value: net,
            color: net >= 0 ? AppColors.savings : AppColors.expense,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        boxShadow: AppShadows.soft(context),
      ),
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: AppSizes.iconSm, color: color),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            CurrencyFormatter.instance.formatCompact(value),
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
