import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/dashboard_widget_type.dart';
import 'dashboard_widget_shell.dart';

/// Icon shown for a not-yet-built [DashboardWidgetType] in the consolidated
/// Coming Soon card — kept in the presentation layer (rather than on the
/// enum itself) so the domain layer stays Flutter-free.
IconData _iconFor(DashboardWidgetType type) {
  switch (type) {
    case DashboardWidgetType.netWorth:
      return Icons.account_balance_wallet_outlined;
    case DashboardWidgetType.financialView:
      return Icons.insights_outlined;
    case DashboardWidgetType.accounts:
      return Icons.account_balance_outlined;
    case DashboardWidgetType.creditCards:
      return Icons.credit_card_outlined;
    case DashboardWidgetType.upcomingPayments:
      return Icons.event_outlined;
    case DashboardWidgetType.bills:
      return Icons.receipt_long_outlined;
    case DashboardWidgetType.emi:
      return Icons.calendar_month_outlined;
    case DashboardWidgetType.loans:
      return Icons.handshake_outlined;
    case DashboardWidgetType.splitExpenses:
      return Icons.call_split_outlined;
    case DashboardWidgetType.savingsGoals:
      return Icons.savings_outlined;
    case DashboardWidgetType.recentActivity:
      return Icons.history_outlined;
    case DashboardWidgetType.budgetProgress:
      return Icons.pie_chart_outline;
    case DashboardWidgetType.people:
      return Icons.people_outline;
    case DashboardWidgetType.cashFlow:
      return Icons.swap_horiz_outlined;
    case DashboardWidgetType.spendingCategories:
      return Icons.category_outlined;
    case DashboardWidgetType.insights:
      return Icons.lightbulb_outline;
    case DashboardWidgetType.calendar:
      return Icons.calendar_today_outlined;
    case DashboardWidgetType.quickActions:
      return Icons.flash_on_outlined;
  }
}

/// One consolidated card for every visible-but-not-yet-built widget, instead
/// of each type rendering its own placeholder card in the View Mode list
/// (which read as a wall of near-identical "X — coming soon" cards). Each
/// [types] entry becomes a compact, disabled tile inside a single [Wrap] —
/// Edit Mode still lists these individually via [DashboardWidgetEditFrame]
/// so hide/reorder/delete keep working per-widget.
class ComingSoonWidgetCard extends StatelessWidget {
  const ComingSoonWidgetCard({super.key, required this.types});

  final List<DashboardWidgetType> types;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final textTheme = context.textTheme;

    return DashboardWidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Coming Soon', style: textTheme.labelLarge),
          const SizedBox(height: AppSizes.xs),
          Text(
            'These will light up in a future update.',
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSizes.md),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: [
              for (final type in types)
                _ComingSoonTile(icon: _iconFor(type), label: type.defaultTitle),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.xs),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSizes.iconSm, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSizes.xs),
          Text(label, style: context.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
