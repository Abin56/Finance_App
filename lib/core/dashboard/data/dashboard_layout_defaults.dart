import '../../../features/reports/domain/reports_period.dart';
import '../domain/dashboard_widget.dart';
import '../domain/dashboard_widget_type.dart';
import '../domain/date_range_strategy.dart';
import '../domain/financial_view_module.dart';
import '../domain/widget_configuration.dart';

/// The dashboard a fresh install (or a user with no saved layout yet) sees —
/// one "Personal" profile covering the same ground the old static dashboard
/// did, so the redesign doesn't regress what's shown by default. Users can
/// hide, reorder, reconfigure, or delete any of these from Edit Mode; this
/// is only ever read once, by [DashboardLayoutController.build], when no
/// saved layout exists.
({List<WidgetConfiguration> configs, List<DashboardLayout> layouts}) buildDefaultDashboard() {
  final configs = <WidgetConfiguration>[
    WidgetConfiguration(id: 'netWorth', type: DashboardWidgetType.netWorth, title: 'Net Worth'),
    // The billing-cycle hero: total spend in the current 17th→17th cycle,
    // with the cycle-progress indicator and next card due date the salary-
    // cycle strategy unlocks in FinancialViewWidgetCard.
    WidgetConfiguration(
      id: 'financialView-salaryCycle',
      type: DashboardWidgetType.financialView,
      title: 'Spent This Pay Period',
      dateStrategy: const SalaryCycleToDate(),
      financialViewModule: FinancialViewModule.combinedExpenses,
    ),
    WidgetConfiguration(id: 'quickActions', type: DashboardWidgetType.quickActions, title: 'Quick Actions'),
    WidgetConfiguration(
      id: 'cashFlow',
      type: DashboardWidgetType.cashFlow,
      title: 'Today',
      dateStrategy: const ReportsPeriodStrategy(ReportsPeriod.today),
    ),
    WidgetConfiguration(id: 'accounts', type: DashboardWidgetType.accounts, title: 'Accounts'),
    WidgetConfiguration(id: 'creditCards', type: DashboardWidgetType.creditCards, title: 'Credit Cards'),
    WidgetConfiguration(
      id: 'upcomingPayments',
      type: DashboardWidgetType.upcomingPayments,
      title: 'Upcoming Payments',
    ),
    WidgetConfiguration(id: 'budgetProgress', type: DashboardWidgetType.budgetProgress, title: 'Budget Health'),
    WidgetConfiguration(id: 'people', type: DashboardWidgetType.people, title: 'People'),
    WidgetConfiguration(id: 'savingsGoals', type: DashboardWidgetType.savingsGoals, title: 'Goals'),
    WidgetConfiguration(id: 'insights', type: DashboardWidgetType.insights, title: 'Insights'),
    WidgetConfiguration(
      id: 'recentActivity',
      type: DashboardWidgetType.recentActivity,
      title: 'Recent Activity',
    ),
  ];

  final layout = DashboardLayout(
    id: 'personal',
    name: 'Personal',
    widgets: [
      const DashboardWidget(id: 'w-netWorth', type: DashboardWidgetType.netWorth, configId: 'netWorth'),
      const DashboardWidget(
        id: 'w-financialView-salaryCycle',
        type: DashboardWidgetType.financialView,
        configId: 'financialView-salaryCycle',
      ),
      const DashboardWidget(id: 'w-quickActions', type: DashboardWidgetType.quickActions, configId: 'quickActions'),
      const DashboardWidget(id: 'w-people', type: DashboardWidgetType.people, configId: 'people'),
      const DashboardWidget(id: 'w-creditCards', type: DashboardWidgetType.creditCards, configId: 'creditCards'),
      const DashboardWidget(id: 'w-cashFlow', type: DashboardWidgetType.cashFlow, configId: 'cashFlow'),
      const DashboardWidget(id: 'w-accounts', type: DashboardWidgetType.accounts, configId: 'accounts'),
      const DashboardWidget(
        id: 'w-upcomingPayments',
        type: DashboardWidgetType.upcomingPayments,
        configId: 'upcomingPayments',
      ),
      const DashboardWidget(
        id: 'w-budgetProgress',
        type: DashboardWidgetType.budgetProgress,
        configId: 'budgetProgress',
      ),
      const DashboardWidget(id: 'w-savingsGoals', type: DashboardWidgetType.savingsGoals, configId: 'savingsGoals'),
      const DashboardWidget(id: 'w-insights', type: DashboardWidgetType.insights, configId: 'insights'),
      const DashboardWidget(
        id: 'w-recentActivity',
        type: DashboardWidgetType.recentActivity,
        configId: 'recentActivity',
      ),
    ],
  );

  return (configs: configs, layouts: [layout]);
}
