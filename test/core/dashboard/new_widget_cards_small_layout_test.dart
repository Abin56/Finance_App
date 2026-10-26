import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/dashboard/domain/dashboard_widget_type.dart';
import 'package:finance_app/core/dashboard/domain/date_range_strategy.dart';
import 'package:finance_app/core/dashboard/presentation/providers/dashboard_display_providers.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/bills_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/calendar_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/cash_flow_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/credit_utilization_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/emi_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/insights_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/loans_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/recent_activity_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/spending_categories_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/split_expenses_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/upcoming_payments_widget_card.dart';
import 'package:finance_app/core/dashboard/domain/widget_configuration.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/shared/widgets/states/section_load_state.dart';
import 'package:finance_app/features/transactions/domain/history_entry.dart';
import 'package:finance_app/shared/domain/transaction_kind.dart';
import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/calendar/presentation/providers/calendar_providers.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/cash_flow/presentation/providers/cash_flow_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/reports/presentation/providers/category_spending_breakdown_provider.dart';
import 'package:finance_app/features/transactions/presentation/providers/history_providers.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';

/// Renders each of Phase 3's new widget-card types on their empty state
/// (every backing provider overridden to an empty/zero value) on a small
/// (360dp) phone, at a couple of text scales — guards against the "See
/// all ›" header row or the empty-state caption overflowing, the same
/// failure class `dashboard_new_widgets_small_layout_test.dart` guards for
/// the earlier-built cards. Non-empty per-card behavior is exercised
/// indirectly via `upcoming_due_provider_test.dart` and
/// `cash_flow_providers_test.dart`, which these cards read from — this
/// file only needs to prove the empty state renders without overflow.
const _smallPhone = Size(360, 640);
const _scales = [1.0, 1.3, 2.0];

void main() {
  final config = WidgetConfiguration(
    id: 'w1',
    type: DashboardWidgetType.bills,
    title: 'A Reasonably Long Widget Title For This Card',
    dateStrategy: const SalaryCycleFull(),
  );

  final overrides = <Override>[
    activeCreditCardsProvider.overrideWithValue(const []),
    creditCardsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    activeEmisProvider.overrideWithValue(const []),
    activeLoansProvider.overrideWithValue(const []),
    billsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    pendingSplitParticipantsProvider.overrideWithValue(const []),
    totalPendingSplitAmountProvider.overrideWithValue(0),
    totalAmountToReceiveProvider.overrideWithValue(0),
    totalCreditCardOutstandingProvider.overrideWithValue(0),
    totalCreditAvailableProvider.overrideWithValue(0),
    categorySpendingBreakdownProvider.overrideWith((ref, args) => const []),
    cashFlowThisMonthProvider.overrideWithValue((
      moneyIn: 0,
      moneyOut: 0,
      net: 0,
    )),
    calendarEventsProvider.overrideWithValue(const []),
    historyEntriesProvider.overrideWithValue(const []),
    calculableTransactionsProvider.overrideWithValue(const []),
    totalRemainingEmiBalanceProvider.overrideWithValue(0),
    // Dashboard 2.0 sections gate on their source streams' load state, so
    // each stream they watch resolves to an empty list here — without this
    // they'd render their error row (no Firebase in this test) instead of
    // the empty state this file is about.
    transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    emisStreamProvider.overrideWith((ref) => Stream.value(const [])),
    loansStreamProvider.overrideWith((ref) => Stream.value(const [])),
    expensesStreamProvider.overrideWith((ref) => Stream.value(const [])),
    categoriesStreamProvider.overrideWith((ref) => Stream.value(const [])),
    dashboardWeeklyCashFlowProvider.overrideWithValue(const [
      (label: '1–7', net: 0),
      (label: '8–14', net: 0),
      (label: '15–21', net: 0),
      (label: '22–31', net: 0),
    ]),
  ];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    double scale,
    Widget child, {
    List<Override>? extraOverrides,
    bool settle = true,
  }) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: extraOverrides == null
            ? overrides
            : [...overrides, ...extraOverrides],
        child: MaterialApp(
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: inner!,
          ),
          home: Scaffold(body: ListView(children: [child])),
        ),
      ),
    );
    // A loading skeleton shimmers indefinitely, so it can never "settle".
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  final cards = <String, Widget Function()>{
    'UpcomingPaymentsWidgetCard': () =>
        UpcomingPaymentsWidgetCard(config: config),
    'BillsWidgetCard': () => BillsWidgetCard(config: config),
    'EmiWidgetCard': () => EmiWidgetCard(config: config),
    'LoansWidgetCard': () => LoansWidgetCard(config: config),
    'SplitExpensesWidgetCard': () => SplitExpensesWidgetCard(config: config),
    'CashFlowWidgetCard': () => CashFlowWidgetCard(config: config),
    'SpendingCategoriesWidgetCard': () =>
        SpendingCategoriesWidgetCard(config: config),
    'CreditUtilizationWidgetCard': () =>
        CreditUtilizationWidgetCard(config: config),
    'CalendarWidgetCard': () => CalendarWidgetCard(config: config),
    'RecentActivityWidgetCard': () => RecentActivityWidgetCard(config: config),
    'InsightsWidgetCard': () => InsightsWidgetCard(config: config),
  };

  for (final scale in _scales) {
    for (final entry in cards.entries) {
      testWidgets(
        '${entry.key} renders its empty state without overflow @${scale}x',
        (tester) async {
          await pumpAt(tester, scale, entry.value());
          expect(tester.takeException(), isNull);
          // Loaded-and-empty must never be drawn as a failure or a skeleton.
          expect(find.textContaining("Couldn't"), findsNothing);
          expect(find.byType(SectionSkeleton), findsNothing);
        },
      );
    }
  }

  // Empty states that used to be a bare grey sentence now read as such
  // (spot-check the redesigned sections).
  testWidgets('redesigned sections show their real empty states', (
    tester,
  ) async {
    await pumpAt(
      tester,
      1.0,
      Column(
        children: [
          UpcomingPaymentsWidgetCard(config: config),
          SpendingCategoriesWidgetCard(config: config),
          CreditUtilizationWidgetCard(config: config),
          RecentActivityWidgetCard(config: config),
        ],
      ),
    );
    expect(find.text('Nothing due this cycle.'), findsOneWidget);
    expect(find.text('No spending in this period yet.'), findsOneWidget);
    expect(find.text('No credit cards yet.'), findsOneWidget);
    expect(
      find.text('No activity yet — your recent entries show here.'),
      findsOneWidget,
    );
  });

  // B2: the Cash Flow header names the period the card actually shows.
  testWidgets('CashFlowWidgetCard titles itself with this month', (
    tester,
  ) async {
    final legacyToday = WidgetConfiguration(
      id: 'cf',
      type: DashboardWidgetType.cashFlow,
      title: 'Today',
    );
    await pumpAt(tester, 1.0, CashFlowWidgetCard(config: legacyToday));
    expect(find.text('Cash flow'), findsOneWidget);
    expect(find.textContaining('This month ·'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });

  // B5: loading and error are distinct from empty.
  testWidgets('a still-loading source shows a skeleton, not "No accounts"', (
    tester,
  ) async {
    await pumpAt(
      tester,
      1.0,
      RecentActivityWidgetCard(config: config),
      extraOverrides: [
        transactionsStreamProvider.overrideWith((ref) => const Stream.empty()),
      ],
      settle: false,
    );
    expect(find.byType(SectionSkeleton), findsOneWidget);
    expect(
      find.text('No activity yet — your recent entries show here.'),
      findsNothing,
    );
  });

  testWidgets('a failed source shows an error row with Retry', (tester) async {
    await pumpAt(
      tester,
      1.0,
      RecentActivityWidgetCard(config: config),
      extraOverrides: [
        transactionsStreamProvider.overrideWith(
          (ref) => Stream.error(StateError('offline')),
        ),
      ],
    );
    expect(find.text("Couldn't load recent activity."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  final now = DateTime.now();
  final longHistoryEntries = [
    HistoryEntry(
      id: 'h1',
      date: now,
      title: 'A Fairly Long Merchant Or Payee Name Here',
      subtitle: 'Groceries',
      amount: 123456.78,
      isCredit: false,
      category: HistoryCategory.transaction,
      icon: Icons.shopping_cart_outlined,
      kind: TransactionKind.myExpense,
    ),
    HistoryEntry(
      id: 'h2',
      date: now.subtract(const Duration(days: 1)),
      title: 'Statement Paid — HDFC Regalia Gold',
      subtitle: 'Card •••• 4321',
      amount: 987654.32,
      isCredit: false,
      category: HistoryCategory.statementPaid,
      icon: Icons.credit_card_rounded,
      kind: TransactionKind.creditCard,
    ),
  ];

  for (final scale in _scales) {
    testWidgets(
      'RecentActivityWidgetCard renders populated entries without overflow @${scale}x',
      (tester) async {
        await pumpAt(
          tester,
          scale,
          RecentActivityWidgetCard(config: config),
          extraOverrides: [
            historyEntriesProvider.overrideWithValue(longHistoryEntries),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text('A Fairly Long Merchant Or Payee Name Here'),
          findsOneWidget,
        );
      },
    );
  }
}
