import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/expense/presentation/widgets/split_expense_form_sheet.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';

/// Regression test for switching from "Add Expense" to "Share Expense":
/// everything already typed in the plain form must carry over into
/// [SplitExpenseFormSheet] via [AddExpenseDraftPrefill], fully editable, and
/// never lost.
void main() {
  Future<void> pump(WidgetTester tester, {AddExpenseDraftPrefill? draft}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const [])),
          peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          home: Scaffold(body: SplitExpenseFormSheet(draft: draft)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final draft = AddExpenseDraftPrefill(
    amount: 450.75,
    description: 'Dinner with friends',
    date: DateTime(2026, 5, 10),
    notes: 'Split the bill',
    excludeFromCalculations: true,
    accountingMonth: DateTime(2026, 6),
  );

  testWidgets('draft prefill populates description, amount, and notes, still editable', (tester) async {
    await pump(tester, draft: draft);

    expect(find.text('Dinner with friends'), findsOneWidget);
    expect(find.text('450.75'), findsOneWidget);
    expect(find.text('Split the bill'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Updated description');
    await tester.pumpAndSettle();
    expect(find.text('Updated description'), findsOneWidget);
  });

  testWidgets('draft prefill turns on "Don\'t count this in my totals" and the accounting month switch', (tester) async {
    await pump(tester, draft: draft);

    final excludeToggle = find.widgetWithText(SwitchListTile, "Don't count this in my totals");
    expect(tester.widget<SwitchListTile>(excludeToggle).value, isTrue);

    final monthToggle = find.widgetWithText(SwitchListTile, 'Count this in a different month?');
    expect(tester.widget<SwitchListTile>(monthToggle).value, isTrue);
  });

  testWidgets('with no draft, fields start blank and switches start off', (tester) async {
    await pump(tester);

    expect(find.text('Dinner with friends'), findsNothing);
    final excludeToggle = find.widgetWithText(SwitchListTile, "Don't count this in my totals");
    expect(tester.widget<SwitchListTile>(excludeToggle).value, isFalse);
  });
}
