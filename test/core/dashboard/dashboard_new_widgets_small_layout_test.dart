import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/core/dashboard/domain/dashboard_widget_type.dart';
import 'package:finance_app/core/dashboard/domain/date_range_strategy.dart';
import 'package:finance_app/core/dashboard/domain/financial_view_module.dart';
import 'package:finance_app/core/dashboard/domain/financial_view_result.dart';
import 'package:finance_app/core/dashboard/domain/widget_configuration.dart';
import 'package:finance_app/core/dashboard/presentation/providers/expense_calculator_provider.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/credit_cards_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/financial_view_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/people_widget_card.dart';
import 'package:finance_app/core/dashboard/presentation/widgets/quick_actions_widget_card.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/reports/domain/reports_period.dart';

/// 360x640 is the standard small Android phone (same baseline as
/// account_detail_screen_small_layout_test.dart). Every new dashboard widget
/// packs amounts beside labels in Rows, so this guards against a large
/// formatted amount or long name overflowing at normal and enlarged text
/// scales — worst-case data on the narrowest supported layout.
const _smallPhone = Size(360, 640);

void main() {
  final now = DateTime.now();

  final heroConfig = WidgetConfiguration(
    id: 'hero',
    type: DashboardWidgetType.financialView,
    title: 'Spent This Cycle',
    dateStrategy: const SalaryCycleToDate(),
    financialViewModule: FinancialViewModule.combinedExpenses,
  );
  final quickActionsConfig = WidgetConfiguration(
    id: 'qa',
    type: DashboardWidgetType.quickActions,
    title: 'Quick Actions',
  );
  final peopleConfig = WidgetConfiguration(
    id: 'people',
    type: DashboardWidgetType.people,
    title: 'People',
  );
  final cardsConfig = WidgetConfiguration(
    id: 'cards',
    type: DashboardWidgetType.creditCards,
    title: 'Credit Cards',
  );

  final people = [
    Person(
      id: 'p1',
      name: 'A Person With A Very Long Name Indeed',
      avatarColorValue: 0xFF000000,
      openingBalance: 0,
      currentBalance: 1234567.89,
      createdAt: DateTime(2026, 1, 1),
    ),
    Person(
      id: 'p2',
      name: 'Someone Else',
      avatarColorValue: 0xFF000000,
      openingBalance: 0,
      currentBalance: -987654.32,
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  final cardAccount = Account(
    id: 'acc1',
    name: 'HDFC Regalia Gold Credit Card',
    type: AccountType.card,
    openingBalance: 0,
    currentBalance: -234567.89,
    colorValue: 0xFF000000,
    createdAt: DateTime(2026, 1, 1),
  );
  final card = CreditCardProfile(
    id: 'card1',
    accountId: 'acc1',
    statementDay: 17,
    paymentDueDay: 5,
    creditLimit: 500000,
    createdAt: DateTime(2026, 1, 1),
    lastFourDigits: '4321',
  );
  final statement = Statement(
    id: 's1',
    cardId: 'card1',
    periodStart: DateTime(now.year, now.month - 1, 17),
    periodEnd: DateTime(now.year, now.month, 17),
    generatedDate: DateTime(now.year, now.month, 17),
    dueDate: now.add(const Duration(days: 3)),
    totalAmount: 234567.89,
    createdAt: DateTime(2026, 1, 1),
  );

  final overrides = <Override>[
    financialViewResultProvider.overrideWith(
      (ref, config) => FinancialViewResult(
        module: config.financialViewModule,
        range: config.dateStrategy.resolve(now),
        amount: 1234567.89,
        previousAmount: 987654.32,
        breakdown: const {
          'My Expenses': 456789.12,
          'Shared Expenses': 123456.78,
          'Credit Card Payments': 654321.99,
        },
      ),
    ),
    peopleStreamProvider.overrideWith((ref) => Stream.value(people)),
    accountsStreamProvider.overrideWith((ref) => Stream.value([cardAccount])),
    creditCardsStreamProvider.overrideWith((ref) => Stream.value([card])),
    sharedCreditLimitsStreamProvider.overrideWith((ref) => Stream.value(const [])),
    statementsStreamProvider.overrideWith((ref, cardId) => Stream.value([statement])),
    statementsWithLiveTotalsProvider.overrideWith((ref, cardId) => [statement]),
    creditCardStandingProvider.overrideWith(
      (ref, cardId) => (outstanding: 434567.89, available: 65432.11, currentCycleSpend: 200000.0),
    ),
    nextStatementDueProvider.overrideWithValue(statement),
  ];

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('new dashboard widgets fit a small phone without overflow @${scale}x', (tester) async {
      tester.view.physicalSize = _smallPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FinancialViewWidgetCard(config: heroConfig),
                  const SizedBox(height: 16),
                  QuickActionsWidgetCard(config: quickActionsConfig),
                  const SizedBox(height: 16),
                  PeopleWidgetCard(config: peopleConfig),
                  const SizedBox(height: 16),
                  CreditCardsWidgetCard(config: cardsConfig),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('You Owe'), findsOneWidget);
      expect(find.text('Owed to You'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Outstanding'), 200);
      expect(find.text('Outstanding'), findsOneWidget);
    });
  }

  testWidgets('billing cycle hero shows cycle progress and next card due', (tester) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(body: FinancialViewWidgetCard(config: heroConfig)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cycle: '), findsOneWidget);
    expect(find.textContaining('Card payment '), findsOneWidget);
    // The plain range caption is replaced by the cycle indicator for
    // salary-cycle strategies, but must still render for other strategies.
    final monthConfig = WidgetConfiguration(
      id: 'month',
      type: DashboardWidgetType.financialView,
      title: 'This Month',
      dateStrategy: const ReportsPeriodStrategy(ReportsPeriod.thisMonth),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(body: FinancialViewWidgetCard(config: monthConfig)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cycle: '), findsNothing);
  });
}
