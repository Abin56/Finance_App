import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/expense/presentation/widgets/assign_expense_sheet.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';

/// Regression test for opening "Add Expense" -> "This person will pay" from
/// a person's own Contact Ledger screen: the person is already known from
/// context, so the sheet must not ask the user to pick them again from a
/// "Person" dropdown (see `PersonStatementScreen`'s `AddExpenseChooser.show`
/// call, which now threads the current person through as `forPerson`).
void main() {
  final person = Person(
    id: 'p1',
    name: 'Jane Doe',
    avatarColorValue: 0xFF000000,
    openingBalance: 0,
    currentBalance: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> pump(WidgetTester tester, {Person? initialPerson}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const [])),
          peopleStreamProvider.overrideWith((ref) => Stream.value([person])),
        ],
        child: MaterialApp(home: Scaffold(body: AssignExpenseSheet(initialPerson: initialPerson))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with no initialPerson, shows the Person dropdown asking the user to pick one', (tester) async {
    await pump(tester);

    expect(find.text('Say who will pay this expense'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Person'), findsOneWidget);
  });

  testWidgets('with initialPerson set, the Person picker is replaced by a locked read-only value', (tester) async {
    await pump(tester, initialPerson: person);

    expect(find.text('Add expense for Jane Doe'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<String>, 'Person'), findsNothing);
    expect(find.text('Jane Doe'), findsWidgets);
  });
}
