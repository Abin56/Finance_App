import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/expense/presentation/widgets/split_expense_form_sheet.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';

/// Regression test: opening "Add Expense" -> "Share with several people"
/// from a person's own Contact Ledger screen should seed the first "share
/// with" row with that person instead of a blank row (see
/// `AddExpenseChooser.show`'s `forPerson` -> `initialParticipant`).
void main() {
  final person = Person(
    id: 'p1',
    name: 'Jane Doe',
    avatarColorValue: 0xFF000000,
    openingBalance: 0,
    currentBalance: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> pump(WidgetTester tester, {Person? initialParticipant}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value(const [])),
          peopleStreamProvider.overrideWith((ref) => Stream.value([person])),
        ],
        child: MaterialApp(
          home: Scaffold(body: SplitExpenseFormSheet(initialParticipant: initialParticipant)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with initialParticipant set, the first share-with row is pre-selected to that person', (tester) async {
    await pump(tester, initialParticipant: person);

    expect(find.widgetWithText(DropdownButtonFormField<String?>, 'Jane Doe'), findsOneWidget);
  });

  testWidgets('with no initialParticipant, the first row starts blank', (tester) async {
    await pump(tester);

    expect(find.widgetWithText(DropdownButtonFormField<String?>, 'Jane Doe'), findsNothing);
  });
}
