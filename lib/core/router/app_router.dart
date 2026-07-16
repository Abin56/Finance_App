import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/presentation/screens/accounts_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/bills/presentation/screens/bill_detail_screen.dart';
import '../../features/bills/presentation/screens/bills_screen.dart';
import '../../features/budget/presentation/screens/budget_screen.dart';
import '../../features/calendar/presentation/screens/calendar_screen.dart';
import '../../features/cash_flow/presentation/screens/cash_flow_screen.dart';
import '../../features/categories/presentation/screens/categories_screen.dart';
import '../../features/credit_cards/presentation/screens/credit_card_detail_screen.dart';
import '../../features/credit_cards/presentation/screens/credit_cards_screen.dart';
import '../../features/credit_cards/presentation/screens/statement_detail_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/emi/presentation/screens/emi_detail_screen.dart';
import '../../features/emi/presentation/screens/emis_screen.dart';
import '../../features/lending/presentation/screens/loan_detail_screen.dart';
import '../../features/lending/presentation/screens/loans_screen.dart';
import '../../features/more/presentation/screens/about_screen.dart';
import '../../features/more/presentation/screens/coming_soon_screen.dart';
import '../../features/more/presentation/screens/more_screen.dart';
import '../../features/more/presentation/screens/trash_hub_screen.dart';
import '../../features/onboarding/presentation/providers/onboarding_providers.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/setup_wizard/presentation/providers/setup_wizard_providers.dart';
import '../../features/setup_wizard/presentation/screens/setup_wizard_screen.dart';
import '../../features/people/presentation/screens/creditors_screen.dart';
import '../../features/people/presentation/screens/debtors_screen.dart';
import '../../features/people/presentation/screens/people_screen.dart';
import '../../features/people/presentation/screens/person_statement_screen.dart';
import '../../features/reports/domain/reports_period.dart';
import '../../features/reports/presentation/screens/category_spending_detail_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/savings/presentation/screens/savings_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/security/presentation/lock_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/transactions/presentation/screens/transaction_detail_screen.dart';
import '../../features/sms_inbox/presentation/screens/sms_inbox_screen.dart';
import '../../features/transactions/presentation/screens/transactions_screen.dart';
import '../services/security/app_lock_controller.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'fab_visibility.dart';
import 'route_error_screen.dart';
import 'router_refresh_notifier.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// App-wide go_router configuration. The bottom-nav tabs (Dashboard,
/// History, Reports, People) each get their own [StatefulShellBranch] so
/// back-stacks stay independent — switching tabs never loses a tab's
/// scroll position or pushed routes. The nav bar's central "+" button opens
/// an add-entry sheet rather than navigating to a branch.
///
/// `redirect` enforces four gates, in priority order:
/// - Onboarding gate: until the intro tour has been seen (finished *or*
///   skipped), every navigation goes to `/onboarding`. It runs ahead of the
///   auth gate on purpose — people should learn what FlowFi does before
///   being asked to sign in — and it means the tour is visible while
///   [authStateProvider] is still resolving in the background.
/// - Auth gate: while [authStateProvider] is resolving, every navigation
///   goes to `/splash`; once resolved, signed-out always goes to `/login`
///   regardless of lock state, and signed-in leaves `/splash`/`/login` for
///   `/dashboard`.
/// - Lock gate (only reached once signed in): whenever [AppLockController]
///   reports `pinEnabled && locked`, every navigation attempt is redirected
///   to `/lock` regardless of where the user was headed.
/// - Setup gate (only reached once signed in and unlocked): until this
///   account has completed *or* dismissed the first-time setup wizard, every
///   navigation goes to `/setup`. Dismissing it marks it done, so it never
///   permanently blocks the app.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = RouterRefreshNotifier(ref);
  final modalCounter = ref.read(modalRouteCountProvider.notifier);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.dashboard,
    debugLogDiagnostics: false,
    refreshListenable: refreshNotifier,
    errorBuilder: (context, state) => const RouteErrorScreen(),
    redirect: (context, state) {
      final goingToOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (!ref.read(onboardingCompletedProvider)) {
        return goingToOnboarding ? null : AppRoutes.onboarding;
      }
      // Seen already: send the tour's own location on, and let the gates
      // below re-resolve it to login or the dashboard.
      if (goingToOnboarding) return AppRoutes.dashboard;

      final authState = ref.read(authStateProvider);
      final goingToSplash = state.matchedLocation == AppRoutes.splash;
      final goingToLogin = state.matchedLocation == AppRoutes.login;

      if (authState.isLoading) {
        return goingToSplash ? null : AppRoutes.splash;
      }

      final isSignedIn = authState.value != null;
      if (!isSignedIn) {
        return goingToLogin ? null : AppRoutes.login;
      }
      if (goingToSplash || goingToLogin) {
        return AppRoutes.dashboard;
      }

      final lockState = ref.read(appLockProvider);
      final isLocked = lockState.pinEnabled && lockState.locked;
      final goingToLock = state.matchedLocation == AppRoutes.lock;

      if (isLocked && !goingToLock) return AppRoutes.lock;
      if (!isLocked && goingToLock) return AppRoutes.dashboard;

      // Setup gate (only reached once signed in and unlocked): first-run
      // configuration for this account. Runs behind the lock so a returning
      // user with a PIN unlocks first, and a step that sets a PIN mid-wizard
      // doesn't bounce them to the lock screen. Skipping the wizard marks it
      // complete, so it never blocks access to the app.
      final goingToSetup = state.matchedLocation == AppRoutes.setupWizard;
      if (!ref.read(setupWizardCompletedProvider)) {
        return goingToSetup ? null : AppRoutes.setupWizard;
      }
      if (goingToSetup) return AppRoutes.dashboard;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.setupWizard,
        builder: (context, state) => const SetupWizardScreen(),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.lock,
        builder: (context, state) => const LockScreen(),
      ),
      GoRoute(
        path: AppRoutes.accounts,
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: AppRoutes.categories,
        builder: (context, state) => const CategoriesScreen(),
      ),
      // Top-level, like every other full-screen drill-in: rendering it inside
      // a shell branch would put it under the shell's FAB and nav bar, and
      // its sheets with it.
      GoRoute(
        path: AppRoutes.smsInbox,
        builder: (context, state) => const SmsInboxScreen(),
      ),
      GoRoute(
        path: AppRoutes.budget,
        builder: (context, state) => const BudgetScreen(),
      ),
      GoRoute(
        path: AppRoutes.savings,
        builder: (context, state) => const SavingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.personStatement,
        builder: (context, state) => PersonStatementScreen(personId: state.pathParameters['personId']!),
      ),
      GoRoute(
        path: AppRoutes.creditors,
        builder: (context, state) => const CreditorsScreen(),
      ),
      GoRoute(
        path: AppRoutes.debtors,
        builder: (context, state) => const DebtorsScreen(),
      ),
      GoRoute(
        path: AppRoutes.loans,
        builder: (context, state) => const LoansScreen(),
      ),
      GoRoute(
        path: AppRoutes.loanDetail,
        builder: (context, state) => LoanDetailScreen(loanId: state.pathParameters['loanId']!),
      ),
      GoRoute(
        path: AppRoutes.emis,
        builder: (context, state) => const EmisScreen(),
      ),
      GoRoute(
        path: AppRoutes.emiDetail,
        builder: (context, state) => EmiDetailScreen(emiId: state.pathParameters['emiId']!),
      ),
      GoRoute(
        path: AppRoutes.bills,
        builder: (context, state) => const BillsScreen(),
      ),
      GoRoute(
        path: AppRoutes.billDetail,
        builder: (context, state) => BillDetailScreen(billId: state.pathParameters['billId']!),
      ),
      GoRoute(
        path: AppRoutes.creditCards,
        builder: (context, state) => const CreditCardsScreen(),
      ),
      GoRoute(
        path: AppRoutes.creditCardDetail,
        builder: (context, state) => CreditCardDetailScreen(cardId: state.pathParameters['cardId']!),
      ),
      GoRoute(
        path: AppRoutes.statementDetail,
        builder: (context, state) => StatementDetailScreen(
          cardId: state.pathParameters['cardId']!,
          statementId: state.pathParameters['statementId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: AppRoutes.transactionDetail,
        builder: (context, state) => TransactionDetailScreen(transactionId: state.pathParameters['transactionId']!),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: AppRoutes.settingsName,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.reports,
        name: AppRoutes.reportsName,
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.reportsCategoryDetail,
        builder: (context, state) {
          final periodName = state.uri.queryParameters['period'];
          final period = ReportsPeriod.values.where((p) => p.name == periodName).firstOrNull;
          return CategorySpendingDetailScreen(
            categoryId: state.pathParameters['categoryId']!,
            initialPeriod: period == ReportsPeriod.custom ? null : period,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.trash,
        builder: (context, state) => const TrashHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.comingSoon,
        builder: (context, state) => const ComingSoonScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        // Every branch observes its own navigator so any sheet or dialog a tab
        // screen opens hides the FAB without the call site knowing. A
        // NavigatorObserver binds to a single Navigator, hence one instance
        // per branch over the shared counter.
        branches: [
          StatefulShellBranch(
            observers: [FabHidingModalObserver(modalCounter)],
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                name: AppRoutes.dashboardName,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [FabHidingModalObserver(modalCounter)],
            routes: [
              GoRoute(
                path: AppRoutes.transactions,
                name: AppRoutes.transactionsName,
                builder: (context, state) =>
                    TransactionsScreen(initialFilterName: state.uri.queryParameters['filter']),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [FabHidingModalObserver(modalCounter)],
            routes: [
              GoRoute(
                path: AppRoutes.cashFlow,
                name: AppRoutes.cashFlowName,
                builder: (context, state) => const CashFlowScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [FabHidingModalObserver(modalCounter)],
            routes: [
              GoRoute(
                path: AppRoutes.people,
                name: AppRoutes.peopleName,
                builder: (context, state) => const PeopleScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [FabHidingModalObserver(modalCounter)],
            routes: [
              GoRoute(
                path: AppRoutes.more,
                name: AppRoutes.moreName,
                builder: (context, state) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
