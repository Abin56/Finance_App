import '../../../features/reports/domain/reports_period.dart';
import '../domain/dashboard_widget.dart';
import '../domain/dashboard_widget_type.dart';
import '../domain/date_range_strategy.dart';
import '../domain/financial_view_module.dart';
import '../domain/widget_configuration.dart';

/// The dashboard a fresh install (or a user with no saved layout yet) sees —
/// one "Personal" profile. Users can hide, reorder, reconfigure, or delete
/// any of these from Edit Mode, and bring them back through Add Widget /
/// Reset; this is read by [DashboardLayoutController.build] when no saved
/// layout exists, by Reset, and as the per-type seed for Add Widget.
///
/// Order follows the dashboard's information-priority hierarchy (mirrors
/// Web's `app/(app)/dashboard/page.tsx`): headline (net worth) → attention
/// (overdue / due next, plus the previous cycle's carry-forward, which the
/// PRD requires near the top) → this month's cash flow and the shortcuts →
/// what's due → cycle spend analysis → composition (accounts, categories,
/// credit) → people → recent activity → insights.
///
/// Only built types ([DashboardWidgetTypeX.isBuilt]) appear here — an
/// unbuilt type would surface as a "Coming Soon" card on every new install.
({List<WidgetConfiguration> configs, List<DashboardLayout> layouts})
buildDefaultDashboard() {
  final configs = <WidgetConfiguration>[
    WidgetConfiguration(
      id: 'netWorth',
      type: DashboardWidgetType.netWorth,
      title: 'Net Worth',
    ),
    WidgetConfiguration(
      id: 'attention',
      type: DashboardWidgetType.attention,
      title: 'Needs Attention',
    ),
    // Previous cycle's carry-forward, kept unmissable near the top per the
    // PRD ("must NOT be hidden, must be visible near the top").
    WidgetConfiguration(
      id: 'previousCycleCarryForward',
      type: DashboardWidgetType.previousCycleCarryForward,
      title: 'Previous Cycle Carry Forward',
      dateStrategy: const SalaryCycleToDate(),
    ),
    // The card always shows this calendar month (`cashFlowThisMonthProvider`)
    // — the strategy is set to match so the stored config never contradicts
    // what's displayed.
    WidgetConfiguration(
      id: 'cashFlow',
      type: DashboardWidgetType.cashFlow,
      title: 'Cash Flow',
      dateStrategy: const ReportsPeriodStrategy(ReportsPeriod.thisMonth),
    ),
    WidgetConfiguration(
      id: 'quickActions',
      type: DashboardWidgetType.quickActions,
      title: 'Quick Actions',
    ),
    WidgetConfiguration(
      id: 'upcomingPayments',
      type: DashboardWidgetType.upcomingPayments,
      title: 'Upcoming Payments',
    ),
    // The billing-cycle spend: total spend in the current 17th→17th cycle,
    // with the cycle-progress indicator the salary-cycle strategy unlocks in
    // FinancialViewWidgetCard.
    WidgetConfiguration(
      id: 'financialView-salaryCycle',
      type: DashboardWidgetType.financialView,
      title: 'Spent This Pay Period',
      dateStrategy: const SalaryCycleToDate(),
      financialViewModule: FinancialViewModule.combinedExpenses,
    ),
    WidgetConfiguration(
      id: 'expenseComparison',
      type: DashboardWidgetType.expenseComparison,
      title: 'My Expenses vs People',
      dateStrategy: const SalaryCycleToDate(),
    ),
    WidgetConfiguration(
      id: 'accounts',
      type: DashboardWidgetType.accounts,
      title: 'Accounts',
    ),
    WidgetConfiguration(
      id: 'spendingCategories',
      type: DashboardWidgetType.spendingCategories,
      title: 'Spending by Category',
    ),
    WidgetConfiguration(
      id: 'creditUtilization',
      type: DashboardWidgetType.creditUtilization,
      title: 'Credit Utilization',
    ),
    WidgetConfiguration(
      id: 'creditCards',
      type: DashboardWidgetType.creditCards,
      title: 'Credit Cards',
    ),
    WidgetConfiguration(
      id: 'people',
      type: DashboardWidgetType.people,
      title: 'People',
    ),
    WidgetConfiguration(
      id: 'recentActivity',
      type: DashboardWidgetType.recentActivity,
      title: 'Recent Activity',
    ),
    WidgetConfiguration(
      id: 'insights',
      type: DashboardWidgetType.insights,
      title: 'Insights',
    ),
  ];

  final layout = DashboardLayout(
    id: 'personal',
    name: 'Personal',
    widgets: [
      for (final c in configs)
        DashboardWidget(id: 'w-${c.id}', type: c.type, configId: c.id),
    ],
  );

  return (configs: configs, layouts: [layout]);
}

/// The default [WidgetConfiguration] for [type], if the default dashboard
/// has one — Add Widget seeds a new instance from it so a re-added widget
/// comes back with its intended date strategy / title rather than bare
/// defaults (e.g. Previous Cycle needs its salary-cycle strategy).
WidgetConfiguration? defaultConfigFor(DashboardWidgetType type) {
  for (final c in buildDefaultDashboard().configs) {
    if (c.type == type) return c;
  }
  return null;
}
