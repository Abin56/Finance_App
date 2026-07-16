import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_expense_screen.dart';

/// Widget-level regression test for the "Exclude from Financial
/// Calculations" toggle and the "Accounting Month" stepper + warning banner
/// added to the Add/Edit Transaction screen — pumps the real widget and
/// drives it like a user would, rather than only unit-testing the
/// underlying calculation logic (covered separately in
/// `transaction_repository_test.dart`/`budget_providers_test.dart`/etc).
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: AddExpenseScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Exclude from Financial Calculations toggle starts off and can be switched on', (tester) async {
    await pump(tester);

    final toggle = find.widgetWithText(SwitchListTile, 'Exclude from Financial Calculations');
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('Accounting Month starts as "Same as Transaction Date" with no stepper or warning shown', (tester) async {
    await pump(tester);

    expect(find.textContaining('Same as Transaction Date'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsNothing);
    expect(find.textContaining('will NOT be included'), findsNothing);
  });

  testWidgets('switching to a different Accounting Month shows the stepper and the warning banner', (tester) async {
    await pump(tester);

    final accountingMonthToggle = find.widgetWithText(SwitchListTile, 'Accounting Month');
    await tester.ensureVisible(accountingMonthToggle);
    await tester.tap(accountingMonthToggle);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Next month'), findsOneWidget);
    // Still on the same month as the transaction date (today) — no warning yet.
    expect(find.textContaining('will NOT be included'), findsNothing);

    await tester.ensureVisible(find.byTooltip('Next month'));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();

    expect(find.textContaining('will NOT be included'), findsOneWidget);
    expect(find.textContaining('Budget, Cash Flow, Dashboard, and Reports'), findsOneWidget);
  });
}
