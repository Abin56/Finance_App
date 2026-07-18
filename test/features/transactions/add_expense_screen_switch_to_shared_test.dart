import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/expense/presentation/widgets/split_expense_form_sheet.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_expense_screen.dart';

/// Regression test for switching from a plain expense to a Shared Expense:
/// data typed into [AddExpenseScreen] must survive the round trip, and
/// backing out of the "Share Expense" sheet must return to the still-live
/// Add Expense screen (not close the whole flow) — see
/// `AddExpenseScreen._switchToSplitExpense`.
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

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([category])),
          peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => AddExpenseScreen.show(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('filling the form then switching to Shared Expense carries the data over, and backing out preserves it',
      (tester) async {
    await pump(tester);

    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), '250'); // Amount
    await tester.pumpAndSettle();
    await tester.enterText(textFields.at(1), 'Team lunch'); // Description
    await tester.pumpAndSettle();

    // Switch to Shared Expense.
    await tester.ensureVisible(find.text('Share Expense'));
    await tester.tap(find.text('Share Expense'));
    await tester.pumpAndSettle();

    // AddExpenseChooser sheet is open, offering the two options.
    expect(find.text('Share with several people'), findsOneWidget);

    // Choose the split flow — should open with the description carried over.
    await tester.tap(find.text('Share with several people'));
    await tester.pumpAndSettle();

    expect(find.text('Team lunch'), findsWidgets);
    expect(find.text('250.00'), findsWidgets);

    // Back out of the sheet without saving, by popping its own Navigator —
    // equivalent to a swipe-down dismiss or the system back gesture.
    Navigator.of(tester.element(find.byType(SplitExpenseFormSheet))).pop();
    await tester.pumpAndSettle();

    // AddExpenseScreen should still be showing, with the original data intact.
    expect(find.text('Add Expense'), findsOneWidget);
    expect(find.text('Team lunch'), findsOneWidget);
  });

  testWidgets('a second back from Add Expense exits the flow', (tester) async {
    await pump(tester);

    expect(find.text('Add Expense'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(navigator.canPop(), isTrue);
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Add Expense'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
