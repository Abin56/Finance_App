import 'package:flutter/material.dart';

import '../../domain/dashboard_widget_type.dart';
import '../../domain/widget_configuration.dart';
import 'accounts_widget_card.dart';
import 'bills_widget_card.dart';
import 'calendar_widget_card.dart';
import 'cash_flow_widget_card.dart';
import 'credit_cards_widget_card.dart';
import 'credit_utilization_widget_card.dart';
import 'emi_widget_card.dart';
import 'financial_view_widget_card.dart';
import 'insights_widget_card.dart';
import 'loans_widget_card.dart';
import 'expense_comparison_widget_card.dart';
import 'net_worth_widget_card.dart';
import 'people_widget_card.dart';
import 'previous_cycle_widget_card.dart';
import 'quick_actions_widget_card.dart';
import 'recent_activity_widget_card.dart';
import 'spending_categories_widget_card.dart';
import 'split_expenses_widget_card.dart';
import 'upcoming_payments_widget_card.dart';

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
      return UpcomingPaymentsWidgetCard(config: config);
    case DashboardWidgetType.bills:
      return BillsWidgetCard(config: config);
    case DashboardWidgetType.emi:
      return EmiWidgetCard(config: config);
    case DashboardWidgetType.loans:
      return LoansWidgetCard(config: config);
    case DashboardWidgetType.splitExpenses:
      return SplitExpensesWidgetCard(config: config);
    case DashboardWidgetType.cashFlow:
      return CashFlowWidgetCard(config: config);
    case DashboardWidgetType.spendingCategories:
      return SpendingCategoriesWidgetCard(config: config);
    case DashboardWidgetType.creditUtilization:
      return CreditUtilizationWidgetCard(config: config);
    case DashboardWidgetType.calendar:
      return CalendarWidgetCard(config: config);
    case DashboardWidgetType.recentActivity:
      return RecentActivityWidgetCard(config: config);
    case DashboardWidgetType.insights:
      return InsightsWidgetCard(config: config);
    case DashboardWidgetType.previousCycleCarryForward:
      return PreviousCycleWidgetCard(config: config);
    case DashboardWidgetType.expenseComparison:
      return ExpenseComparisonWidgetCard(config: config);
    case DashboardWidgetType.savingsGoals:
    case DashboardWidgetType.budgetProgress:
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
