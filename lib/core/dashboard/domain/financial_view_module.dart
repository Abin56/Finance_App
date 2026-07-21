/// What a Financial View widget totals for its resolved date range. Each
/// [WidgetConfiguration] for a `financialView` widget picks exactly one —
/// switching modules never changes the date strategy, so a user can compare
/// "My Expenses this Salary Cycle" against "Income this Salary Cycle" by
/// editing the same widget, or keep both as separate instances.
enum FinancialViewModule {
  myExpenses,
  sharedExpenses,
  combinedExpenses,
  income,
  transfers,
  netCashFlow,
}

extension FinancialViewModuleX on FinancialViewModule {
  String get label {
    switch (this) {
      case FinancialViewModule.myExpenses:
        return 'My Expenses';
      case FinancialViewModule.sharedExpenses:
        return 'Shared Expenses';
      case FinancialViewModule.combinedExpenses:
        return 'Combined Expenses';
      case FinancialViewModule.income:
        return 'Income';
      case FinancialViewModule.transfers:
        return 'Transfers';
      case FinancialViewModule.netCashFlow:
        return 'Net Cash Flow';
    }
  }
}
