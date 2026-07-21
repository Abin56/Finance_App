import 'package:flutter/material.dart';

import '../../domain/dashboard_widget_type.dart';
import '../../domain/widget_configuration.dart';
import 'accounts_widget_card.dart';
import 'credit_cards_widget_card.dart';
import 'financial_view_widget_card.dart';
import 'net_worth_widget_card.dart';
import 'people_widget_card.dart';
import 'quick_actions_widget_card.dart';

/// Maps a [DashboardWidgetType] to the widget that renders it. This is the
/// single place a new type gets wired in — the dashboard shell, Edit Mode
/// chrome, and persistence layer never grow a case for a specific type.
/// Types with no builder yet ([DashboardWidgetTypeX.isBuilt] false) render a
/// generic placeholder card here — used only by Edit Mode, where each widget
/// still needs its own row to hide/reorder/delete. View Mode instead groups
/// every unbuilt type into one [ComingSoonWidgetCard] (see
/// `_ViewModeList` in `dashboard_screen.dart`) rather than rendering this
/// placeholder once per type.
Widget buildDashboardWidget(DashboardWidgetType type, WidgetConfiguration config, {VoidCallback? onConfigure}) {
  switch (type) {
    case DashboardWidgetType.netWorth:
      return NetWorthWidgetCard(config: config);
    case DashboardWidgetType.financialView:
      return FinancialViewWidgetCard(config: config, onConfigure: onConfigure);
    case DashboardWidgetType.accounts:
      return AccountsWidgetCard(config: config);
    case DashboardWidgetType.creditCards:
      return CreditCardsWidgetCard(config: config);
    case DashboardWidgetType.people:
      return PeopleWidgetCard(config: config);
    case DashboardWidgetType.quickActions:
      return QuickActionsWidgetCard(config: config);
    case DashboardWidgetType.upcomingPayments:
    case DashboardWidgetType.bills:
    case DashboardWidgetType.emi:
    case DashboardWidgetType.loans:
    case DashboardWidgetType.splitExpenses:
    case DashboardWidgetType.savingsGoals:
    case DashboardWidgetType.recentActivity:
    case DashboardWidgetType.budgetProgress:
    case DashboardWidgetType.cashFlow:
    case DashboardWidgetType.spendingCategories:
    case DashboardWidgetType.insights:
    case DashboardWidgetType.calendar:
      return _NotYetBuiltCard(type: type);
  }
}

/// Placeholder for a catalog entry that has no builder yet — keeps the
/// widget list navigable/addable end-to-end while implementation catches up
/// type by type, rather than hiding unbuilt types from Edit Mode entirely.
class _NotYetBuiltCard extends StatelessWidget {
  const _NotYetBuiltCard({required this.type});

  final DashboardWidgetType type;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('${type.defaultTitle} — coming soon', style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
