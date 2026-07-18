import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_expense_screen.dart';

/// Regression test for the optional "Person" field on the plain (non-shared)
/// Add Expense screen — a pure reference (`Transaction.linkedPersonId`), so
/// it must be selectable/clearable without ever touching split/ledger code.
void main() {
  final account = Account(
    id: 'acc1',
    name: 'Cash',
    type: AccountType.cash,
    openingBalance: 0,
    currentBalance: 0,
    colorValue: 0xFF00FF00,
    createdAt: DateTime(2026, 1, 1),
  );
  final category = Category(
    id: 'cat1',
    name: 'Food',
    iconKey: 'restaurant',
    colorValue: 0xFFFF0000,
    type: CategoryType.expense,
    createdAt: DateTime(2026, 1, 1),
  );
  final person = Person(
    id: 'p1',
    name: 'Rahul Sharma',
    avatarColorValue: 0xFF000000,
    openingBalance: 0,
    currentBalance: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([category])),
          peopleStreamProvider.overrideWith((ref) => Stream.value([person])),
        ],
        child: const MaterialApp(home: AddExpenseScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Person field starts empty and optional, for an expense-type transaction', (tester) async {
    await pump(tester);

    expect(find.text('Person (optional)'), findsOneWidget);
    expect(find.text('Add a person (optional)'), findsOneWidget);
  });

  testWidgets('selecting a person shows their name and a clear action', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Add a person (optional)'));
    await tester.pumpAndSettle();

    expect(find.text('Rahul Sharma'), findsWidgets); // picker sheet list entry
    await tester.tap(find.text('Rahul Sharma').last);
    await tester.pumpAndSettle();

    expect(find.text('Rahul Sharma'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsWidgets);
  });

  testWidgets('clearing a selected person returns to the empty/optional state', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Add a person (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rahul Sharma').last);
    await tester.pumpAndSettle();
    expect(find.text('Rahul Sharma'), findsOneWidget);

    // The clear (x) icon inside the Person row.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.cancel).last);
    await tester.pumpAndSettle();

    expect(find.text('Add a person (optional)'), findsOneWidget);
  });
}
