import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/dashboard/domain/dashboard_widget_type.dart';
import 'package:finance_app/core/dashboard/domain/widget_configuration.dart';
import 'package:finance_app/core/dashboard/presentation/providers/dashboard_display_providers.dart';
import 'package:finance_app/core/dashboard/presentation/providers/upcoming_due_provider.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/accounts_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/add_dashboard_widget_sheet.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/attention_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/cash_flow_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/credit_utilization_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/net_worth_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/upcoming_payments_widget_card.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/lending/domain/loan_balance_sheet.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_balance_sheet_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';

/// Dashboard 2.0 sections on a 360×640 phone, light and dark Theme V2, at
/// 1.0 / 1.3 / 2.0 text scale, with worst-case (very large) figures — the
/// overflow guard for the redesigned hero, attention strip, cash flow,
/// accounts and credit sections, plus the behaviours they promise.
const _smallPhone = Size(360, 640);

void main() {
  final created = DateTime(2025, 1, 1);
  final bank = Account(
    id: 'bank',
    name: 'A Savings Account With A Very Long Display Name',
    type: AccountType.bank,
    openingBalance: 0,
    currentBalance: 98765432.1,
    colorValue: 0xFF1565C0,
    createdAt: created,
  );
  final cardAccount = Account(
    id: 'cardAcc',
    name: 'HDFC Regalia Gold',
    type: AccountType.card,
    openingBalance: 0,
    currentBalance: -234567.89,
    colorValue: 0xFF000000,
    createdAt: created,
  );
  final card = CreditCardProfile(
    id: 'card1',
    accountId: 'cardAcc',
    statementDay: 17,
    paymentDueDay: 5,
    creditLimit: 500000,
    createdAt: created,
    lastFourDigits: '4321',
  );
  final today = DateTime.now();

  UpcomingDueItem item(UpcomingDueKind kind, int days, double remaining) => (
    kind: kind,
    title: 'An Electricity Bill With A Long Provider Name',
    dueDate: today.add(Duration(days: days)),
    remaining: remaining,
    urgency: days < 0 ? PaymentUrgency.overdue : PaymentUrgency.upcoming,
    isCarriedOver: false,
    routeId: 'r',
    secondaryRouteId: null,
  );
  final upcoming = [
    item(UpcomingDueKind.bill, -4, 123456.78),
    item(UpcomingDueKind.creditCard, -1, 98765.43),
    item(UpcomingDueKind.emi, 3, 25000),
    item(UpcomingDueKind.splitExpense, 2, 4500),
  ];

  List<Override> overrides({NetWorthTrend? trend}) => [
    accountsStreamProvider.overrideWith(
      (ref) => Stream.value([bank, cardAccount]),
    ),
    creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
    loansStreamProvider.overrideWith((ref) => Stream.value(const [])),
    emisStreamProvider.overrideWith((ref) => Stream.value(const [])),
    peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
    billsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    expensesStreamProvider.overrideWith((ref) => Stream.value(const [])),
    transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    netWorthWithLoansProvider.overrideWithValue(123456789.12),
    loanBalanceSheetProvider.overrideWithValue(LoanBalanceSheet.empty),
    liabilityTotalsProvider.overrideWithValue(
      const LiabilityTotals(creditCards: 234567.89, loans: 8500000, emis: 0),
    ),
    netWorthTrendProvider.overrideWithValue(
      trend ??
          const NetWorthTrend.available([
            120000000,
            121500000,
            121000000,
            122800000,
            123000000,
            123300000,
            123456789.12,
          ]),
    ),
    upcomingDueProvider.overrideWith((ref, cycle) => upcoming),
    cashFlowThisMonthProvider.overrideWithValue((
      moneyIn: 1234567.89,
      moneyOut: 987654.32,
      net: 246913.57,
    )),
    dashboardWeeklyCashFlowProvider.overrideWithValue(const [
      (label: '1–7', net: 900000),
      (label: '8–14', net: -400000),
      (label: '15–21', net: -253086.43),
      (label: '22–31', net: 0),
    ]),
    cashBalanceProvider.overrideWithValue(98765432.1),
    activeCreditCardsProvider.overrideWithValue([card]),
    totalCreditCardOutstandingProvider.overrideWithValue(434567.89),
    totalCreditAvailableProvider.overrideWithValue(65432.11),
    creditCardStandingProvider.overrideWith(
      (ref, id) =>
          (outstanding: 434567.89, available: 65432.11, currentCycleSpend: 0),
    ),
  ];

  WidgetConfiguration config(DashboardWidgetType type) =>
      WidgetConfiguration(id: type.name, type: type, title: type.defaultTitle);

  Future<void> pump(
    WidgetTester tester, {
    required ThemeData theme,
    required double scale,
    required List<Widget> children,
    NetWorthTrend? trend,
  }) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(trend: trend),
        child: MaterialApp(
          theme: theme,
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: inner!,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: children,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    LocalSettingsService.resetForTest();
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  final themes = <String, ThemeData Function()>{
    'light': () => AppTheme.light,
    'dark': () => AppTheme.dark,
  };
  for (final theme in themes.entries) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
        'Dashboard 2.0 sections fit a small phone (${theme.key}) @${scale}x',
        (tester) async {
          final sections = [
            NetWorthWidgetCard(config: config(DashboardWidgetType.netWorth)),
            AttentionWidgetCard(config: config(DashboardWidgetType.attention)),
            CashFlowWidgetCard(config: config(DashboardWidgetType.cashFlow)),
            UpcomingPaymentsWidgetCard(
              config: config(DashboardWidgetType.upcomingPayments),
            ),
            AccountsWidgetCard(config: config(DashboardWidgetType.accounts)),
            CreditUtilizationWidgetCard(
              config: config(DashboardWidgetType.creditUtilization),
            ),
          ];
          // One section per pump so the lazily-built ListView can't hide an
          // overflow below the fold.
          for (final section in sections) {
            await pump(
              tester,
              theme: theme.value(),
              scale: scale,
              children: [section],
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${section.runtimeType}',
            );
          }
        },
      );
    }
  }

  testWidgets('hero shows Assets / Debt and the real trend', (tester) async {
    await pump(
      tester,
      theme: AppTheme.light,
      scale: 1.0,
      children: [
        NetWorthWidgetCard(config: config(DashboardWidgetType.netWorth)),
      ],
    );
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Debt'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
  });

  testWidgets('hero says the trend is unavailable instead of guessing', (
    tester,
  ) async {
    await pump(
      tester,
      theme: AppTheme.dark,
      scale: 1.0,
      trend: const NetWorthTrend.unavailable(),
      children: [
        NetWorthWidgetCard(config: config(DashboardWidgetType.netWorth)),
      ],
    );
    expect(find.textContaining('7-day trend unavailable'), findsOneWidget);
    expect(find.text('Last 7 days'), findsNothing);
  });

  testWidgets('hiding net worth is remembered on this device', (tester) async {
    await pump(
      tester,
      theme: AppTheme.light,
      scale: 1.0,
      children: [
        NetWorthWidgetCard(config: config(DashboardWidgetType.netWorth)),
      ],
    );
    await tester.tap(find.byTooltip('Hide net worth'));
    await tester.pumpAndSettle();
    expect(find.text('₹ ••••••'), findsOneWidget);
    expect(LocalSettingsService.getBool('dashboard_hide_net_worth'), isTrue);
  });

  testWidgets('attention strip sums overdue and excludes receivables', (
    tester,
  ) async {
    await pump(
      tester,
      theme: AppTheme.light,
      scale: 1.0,
      children: [
        AttentionWidgetCard(config: config(DashboardWidgetType.attention)),
      ],
    );
    expect(find.text('2 PAYMENTS OVERDUE'), findsOneWidget);
    expect(find.text('₹2,22,222'), findsOneWidget); // 123456.78 + 98765.43
    expect(find.text('DUE NEXT'), findsOneWidget);
    expect(find.text('₹25,000'), findsOneWidget); // the EMI, not the split
  });

  testWidgets('upcoming payments list receivables separately', (tester) async {
    await pump(
      tester,
      theme: AppTheme.light,
      scale: 1.0,
      children: [
        UpcomingPaymentsWidgetCard(
          config: config(DashboardWidgetType.upcomingPayments),
        ),
      ],
    );
    expect(find.text('Coming In From People'), findsOneWidget);
    // Header counts / totals outgoing rows only (3 of the 4 items).
    expect(find.textContaining('3 due this cycle'), findsOneWidget);
  });

  testWidgets('accounts total excludes the card account', (tester) async {
    await pump(
      tester,
      theme: AppTheme.light,
      scale: 1.0,
      children: [
        AccountsWidgetCard(config: config(DashboardWidgetType.accounts)),
      ],
    );
    expect(find.text('HDFC Regalia Gold'), findsNothing);
    expect(
      find.textContaining('1 credit card account shown under Credit'),
      findsOneWidget,
    );
  });

  testWidgets('Add widget sheet marks placed widgets and offers the rest', (
    tester,
  ) async {
    await pump(
      tester,
      theme: AppTheme.light,
      scale: 1.0,
      children: [
        Builder(
          builder: (context) => TextButton(
            onPressed: () => AddDashboardWidgetSheet.show(context),
            child: const Text('open'),
          ),
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add widget'), findsOneWidget);
    // Net Worth is on the default dashboard; Bills is not.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Net Worth'),
        matching: find.text('On your dashboard'),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Bills'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Bills'),
        matching: find.text('Adds to the end — drag to reorder'),
      ),
      findsOneWidget,
    );
  });
}
