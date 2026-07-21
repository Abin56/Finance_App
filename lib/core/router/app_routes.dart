/// Centralized route paths and names so screens never hardcode strings
/// when navigating with go_router.
abstract class AppRoutes {
  AppRoutes._();

  // First run
  static const String onboarding = '/onboarding';
  static const String setupWizard = '/setup';

  // Auth
  static const String splash = '/splash';
  static const String login = '/login';

  // Shell tabs
  static const String dashboard = '/dashboard';
  static const String transactions = '/transactions';
  static const String cashFlow = '/cash-flow';
  static const String people = '/people';
  static const String more = '/more';

  // Pushed routes
  static const String reports = '/reports';
  static const String reportsCategoryDetail = '/reports/category/:categoryId';
  static const String settings = '/settings';
  static const String about = '/about';
  static const String trash = '/trash';
  static const String comingSoon = '/coming-soon';
  static const String categories = '/categories';
  static const String budget = '/budget';
  static const String savings = '/savings';
  static const String creditors = '/creditors';
  static const String debtors = '/debtors';
  static const String personStatement = '/people/:personId';
  static const String loans = '/loans';
  static const String loanDetail = '/loans/:loanId';
  static const String emis = '/emis';
  static const String emiDetail = '/emis/:emiId';
  static const String bills = '/bills';
  static const String billDetail = '/bills/:billId';
  static const String creditCards = '/creditCards';
  static const String creditCardDetail = '/creditCards/:cardId';
  static const String statementDetail = '/creditCards/:cardId/statements/:statementId';
  static const String transactionDetail = '/transactions/:transactionId';
  static const String calendar = '/calendar';
  static const String search = '/search';
  static const String accounts = '/accounts';
  static const String accountDetail = '/accounts/:accountId';
  static const String smsInbox = '/sms-inbox';
  static const String lock = '/lock';

  static const String dashboardName = 'dashboard';
  static const String transactionsName = 'transactions';
  static const String cashFlowName = 'cashFlow';
  static const String peopleName = 'people';
  static const String moreName = 'more';
  static const String reportsName = 'reports';
  static const String settingsName = 'settings';
}
