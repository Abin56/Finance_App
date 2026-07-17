import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_expense_screen.dart';

/// Widget-level regression test for the "Don't count this in my totals"
/// (excludeFromCalculations) toggle and the "Count this in a different
/// month?" (accountingMonth) stepper + warning banner added to the Add/Edit
/// Transaction screen — pumps the real widget and drives it like a user
/// would, rather than only unit-testing the underlying calculation logic
/// (covered separately in
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

  testWidgets('"Don\'t count this in my totals" toggle starts off and can be switched on', (tester) async {
    await pump(tester);

    final toggle = find.widgetWithText(SwitchListTile, "Don't count this in my totals");
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('Accounting Month starts as "counted in the transaction\'s own month" with no stepper or warning',
      (tester) async {
    await pump(tester);

    expect(find.textContaining('Right now: counted in'), findsOneWidget);
    expect(find.byTooltip('Next month'), findsNothing);
    expect(find.textContaining("won't count in"), findsNothing);
  });

  testWidgets('switching to a different Accounting Month shows the stepper and the warning banner', (tester) async {
    await pump(tester);

    final accountingMonthToggle = find.widgetWithText(SwitchListTile, 'Count this in a different month?');
    await tester.ensureVisible(accountingMonthToggle);
    await tester.tap(accountingMonthToggle);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Next month'), findsOneWidget);
    // Still on the same month as the transaction date (today) — no warning yet.
    expect(find.textContaining("won't count in"), findsNothing);

    await tester.ensureVisible(find.byTooltip('Next month'));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();

    expect(find.textContaining("won't count in"), findsOneWidget);
    expect(find.textContaining('Budget, Cash Flow, Dashboard, and Reports'), findsOneWidget);
  });
}
