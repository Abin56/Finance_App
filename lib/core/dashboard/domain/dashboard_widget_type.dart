/// Every widget type the dashboard can render. Adding a new type here (plus
/// a case in the widget-registry's builder map) is the only change needed to
/// plug in a new widget — the shell, persistence, and Edit Mode chrome never
/// need to know about a specific type.
enum DashboardWidgetType {
  netWorth,
  financialView,
  accounts,
  creditCards,
  upcomingPayments,
  bills,
  emi,
  loans,
  splitExpenses,
  savingsGoals,
  recentActivity,
  budgetProgress,
  people,
  cashFlow,
  spendingCategories,
  insights,
  calendar,
  quickActions,
}

extension DashboardWidgetTypeX on DashboardWidgetType {
  /// Display name used as the default [WidgetConfiguration.title] and in the
  /// "Add Widget" picker.
  String get defaultTitle {
    switch (this) {
      case DashboardWidgetType.netWorth:
        return 'Net Worth';
      case DashboardWidgetType.financialView:
        return 'Financial View';
      case DashboardWidgetType.accounts:
        return 'Accounts';
      case DashboardWidgetType.creditCards:
        return 'Credit Cards';
      case DashboardWidgetType.upcomingPayments:
        return 'Upcoming Payments';
      case DashboardWidgetType.bills:
        return 'Bills';
      case DashboardWidgetType.emi:
        return 'EMIs';
      case DashboardWidgetType.loans:
        return 'Loans';
      case DashboardWidgetType.splitExpenses:
        return 'Split Expenses';
      case DashboardWidgetType.savingsGoals:
        return 'Savings Goals';
      case DashboardWidgetType.recentActivity:
        return 'Recent Activity';
      case DashboardWidgetType.budgetProgress:
        return 'Budget Progress';
      case DashboardWidgetType.people:
        return 'People';
      case DashboardWidgetType.cashFlow:
        return 'Cash Flow';
      case DashboardWidgetType.spendingCategories:
        return 'Spending Categories';
      case DashboardWidgetType.insights:
        return 'Insights';
      case DashboardWidgetType.calendar:
        return 'Calendar';
      case DashboardWidgetType.quickActions:
        return 'Quick Actions';
    }
  }

  /// Whether more than one independent instance of this type may exist on
  /// the same dashboard at once (e.g. three Financial View widgets, each on
  /// its own date strategy). Singleton widgets (Net Worth, Quick Actions, …)
  /// still use the same [WidgetConfiguration] shape, just capped at one
  /// instance by the Add Widget flow.
  bool get supportsMultipleInstances {
    switch (this) {
      case DashboardWidgetType.financialView:
        return true;
      default:
        return false;
    }
  }

  /// Whether [dashboard_widget_registry.buildDashboardWidget] has a real
  /// renderer for this type yet. Types without one are grouped into a single
  /// "Coming Soon" card in View Mode rather than each rendering their own
  /// placeholder card — see `_ViewModeList` in `dashboard_screen.dart`.
  bool get isBuilt {
    switch (this) {
      case DashboardWidgetType.netWorth:
      case DashboardWidgetType.financialView:
      case DashboardWidgetType.accounts:
      case DashboardWidgetType.creditCards:
      case DashboardWidgetType.people:
      case DashboardWidgetType.quickActions:
        return true;
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
        return false;
    }
  }

}

/// Compact / Medium / Large — how much space a widget instance occupies and
/// how much detail it renders. Every widget builder should honor this rather
/// than always rendering its largest layout.
enum DashboardWidgetSize { compact, medium, large }
