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
///
/// Order follows the dashboard's information-priority hierarchy: hero →
/// carry-forward alert → my-expense-vs-people → what's due/actionable →
/// financial snapshot (accounts/credit cards/people) → cash flow → insights
/// → recent activity teaser, with not-yet-built types trailing at the end
/// (they're collapsed into a single "Coming Soon" card in View Mode
/// regardless of position).
({List<WidgetConfiguration> configs, List<DashboardLayout> layouts}) buildDefaultDashboard() {
  final configs = <WidgetConfiguration>[
    WidgetConfiguration(id: 'netWorth', type: DashboardWidgetType.netWorth, title: 'Net Worth'),
    // The billing-cycle hero: total spend in the current 17th→17th cycle,
    // with the cycle-progress indicator the salary-cycle strategy unlocks in
    // FinancialViewWidgetCard.
    WidgetConfiguration(
      id: 'financialView-salaryCycle',
      type: DashboardWidgetType.financialView,
      title: 'Spent This Pay Period',
      dateStrategy: const SalaryCycleToDate(),
      financialViewModule: FinancialViewModule.combinedExpenses,
    ),
    // Previous cycle's carry-forward, kept unmissable right under the
    // hero per the PRD ("must NOT be hidden, must be visible near the
    // top") — same salary-cycle anchor as the hero above it.
    WidgetConfiguration(
      id: 'previousCycleCarryForward',
      type: DashboardWidgetType.previousCycleCarryForward,
      title: 'Previous Cycle Carry Forward',
      dateStrategy: const SalaryCycleToDate(),
    ),
    WidgetConfiguration(
      id: 'expenseComparison',
      type: DashboardWidgetType.expenseComparison,
      title: 'My Expenses vs People',
      dateStrategy: const SalaryCycleToDate(),
    ),
    WidgetConfiguration(
      id: 'upcomingPayments',
      type: DashboardWidgetType.upcomingPayments,
      title: 'Upcoming Payments',
    ),
    WidgetConfiguration(id: 'quickActions', type: DashboardWidgetType.quickActions, title: 'Quick Actions'),
    WidgetConfiguration(id: 'accounts', type: DashboardWidgetType.accounts, title: 'Accounts'),
    WidgetConfiguration(id: 'creditCards', type: DashboardWidgetType.creditCards, title: 'Credit Cards'),
    WidgetConfiguration(id: 'people', type: DashboardWidgetType.people, title: 'People'),
    WidgetConfiguration(
      id: 'cashFlow',
      type: DashboardWidgetType.cashFlow,
      title: 'Today',
      dateStrategy: const ReportsPeriodStrategy(ReportsPeriod.today),
    ),
    WidgetConfiguration(id: 'insights', type: DashboardWidgetType.insights, title: 'Insights'),
    WidgetConfiguration(
      id: 'recentActivity',
      type: DashboardWidgetType.recentActivity,
      title: 'Recent Activity',
    ),
    WidgetConfiguration(id: 'budgetProgress', type: DashboardWidgetType.budgetProgress, title: 'Budget Health'),
    WidgetConfiguration(id: 'savingsGoals', type: DashboardWidgetType.savingsGoals, title: 'Goals'),
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
      const DashboardWidget(
        id: 'w-previousCycleCarryForward',
        type: DashboardWidgetType.previousCycleCarryForward,
        configId: 'previousCycleCarryForward',
      ),
      const DashboardWidget(
        id: 'w-expenseComparison',
        type: DashboardWidgetType.expenseComparison,
        configId: 'expenseComparison',
      ),
      const DashboardWidget(
        id: 'w-upcomingPayments',
        type: DashboardWidgetType.upcomingPayments,
        configId: 'upcomingPayments',
      ),
      const DashboardWidget(id: 'w-quickActions', type: DashboardWidgetType.quickActions, configId: 'quickActions'),
      const DashboardWidget(id: 'w-accounts', type: DashboardWidgetType.accounts, configId: 'accounts'),
      const DashboardWidget(id: 'w-creditCards', type: DashboardWidgetType.creditCards, configId: 'creditCards'),
      const DashboardWidget(id: 'w-people', type: DashboardWidgetType.people, configId: 'people'),
      const DashboardWidget(id: 'w-cashFlow', type: DashboardWidgetType.cashFlow, configId: 'cashFlow'),
      const DashboardWidget(id: 'w-insights', type: DashboardWidgetType.insights, configId: 'insights'),
      const DashboardWidget(
        id: 'w-recentActivity',
        type: DashboardWidgetType.recentActivity,
        configId: 'recentActivity',
      ),
      const DashboardWidget(
        id: 'w-budgetProgress',
        type: DashboardWidgetType.budgetProgress,
        configId: 'budgetProgress',
      ),
      const DashboardWidget(id: 'w-savingsGoals', type: DashboardWidgetType.savingsGoals, configId: 'savingsGoals'),
    ],
  );

  return (configs: configs, layouts: [layout]);
}
