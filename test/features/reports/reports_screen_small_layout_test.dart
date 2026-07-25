import 'package:finance_app/features/bills/presentation/providers/bill_providers.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/credit_cards/presentation/providers/credit_card_providers.dart';
import 'package:finance_app/features/emi/presentation/providers/emi_providers.dart';
import 'package:finance_app/features/expense/presentation/providers/expense_providers.dart';
import 'package:finance_app/features/lending/presentation/providers/loan_providers.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';

/// Pumps the real [ReportsScreen] (not an isolated widget) with a realistic
/// set of transactions across two months, on a small (360dp) phone at a
/// couple of text scales — this is the only place every one of Phase 5's
/// new sections (Spending Trend, Monthly Comparison, Category pie +
/// list, Financial Health) render stacked together in their real order, so
/// it's the test most likely to catch a cross-section overflow the
/// individual widget-level tests wouldn't.
const _smallPhone = Size(360, 640);
const _scales = [1.0, 1.3];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  final now = DateTime.now();
  final groceries = Category(
    id: 'cat1',
    name: 'Groceries',
    type: CategoryType.expense,
    iconKey: 'groceries',
    colorValue: 0xFF00FF00,
    createdAt: now,
  );
  final salary = Category(
    id: 'cat2',
    name: 'Salary',
    type: CategoryType.income,
    iconKey: 'salary',
    colorValue: 0xFF0000FF,
    createdAt: now,
  );

  Transaction tx({
    required String id,
    required TransactionType type,
    required double amount,
    required DateTime date,
    required String categoryId,
  }) {
    return Transaction(
      id: id,
      type: type,
      amount: amount,
      dateTime: date,
      accountId: 'acc1',
      categoryId: categoryId,
      createdAt: date,
    );
  }

  final transactions = [
    tx(id: 't1', type: TransactionType.expense, amount: 12345.67, date: now, categoryId: groceries.id),
    tx(
      id: 't2',
      type: TransactionType.expense,
      amount: 98765.43,
      date: now.subtract(const Duration(days: 3)),
      categoryId: groceries.id,
    ),
    tx(id: 't3', type: TransactionType.income, amount: 200000, date: now, categoryId: salary.id),
    tx(
      id: 't4',
      type: TransactionType.income,
      amount: 180000,
      date: DateTime(now.year, now.month - 1, 15),
      categoryId: salary.id,
    ),
  ];

  Future<void> pumpAt(WidgetTester tester, double scale) async {
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calculableTransactionsProvider.overrideWithValue(transactions),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([groceries, salary])),
          emisStreamProvider.overrideWith((ref) => Stream.value(const [])),
          creditCardsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          activeCreditCardsProvider.overrideWithValue(const []),
          billsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          loansStreamProvider.overrideWith((ref) => Stream.value(const [])),
          peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
          pendingSplitExpensesProvider.overrideWithValue(const []),
          pendingSplitParticipantsProvider.overrideWithValue(const []),
          expensesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: inner!,
          ),
          home: const ReportsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in _scales) {
    testWidgets('Reports screen renders every Phase 5 section without overflow @${scale}x', (tester) async {
      await pumpAt(tester, scale);
      expect(tester.takeException(), isNull);

      Future<void> scrollUntilFound(String text) async {
        for (var i = 0; i < 20 && find.text(text).evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -300));
          await tester.pump();
        }
        expect(tester.takeException(), isNull, reason: 'overflow while scrolling to "$text"');
        expect(find.text(text), findsOneWidget);
      }

      await scrollUntilFound('Spending Trend');
      await scrollUntilFound('Monthly Comparison');
      await scrollUntilFound('Financial Health');
    });
  }
}
