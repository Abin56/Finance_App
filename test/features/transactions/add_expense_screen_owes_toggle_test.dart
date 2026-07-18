import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_expense_screen.dart';

/// Regression test for Bug 1/2's real fix: selecting a Person on a plain
/// Add Expense must stay a pure reference by default (no ledger, no balance
/// change), and only the explicit "This person owes me this expense" toggle
/// should route the save through `ExpenseRepository` — proving the two
/// behaviors stay genuinely separate rather than always creating a ledger
/// entry (the bug) or never doing so (breaking the toggle's whole purpose).
const _kUid = 'test-uid';

void main() {
  late FakeFirebaseFirestore firestore;

  Future<void> seedAccount() async {
    await firestore.collection('users').doc(_kUid).collection('accounts').doc('acc1').set({
      'name': 'Cash',
      'type': AccountType.cash.name,
      'openingBalance': 1000.0,
      'currentBalance': 1000.0,
      'colorValue': 0xFF00FF00,
      'isDefault': false,
      'createdAt': DateTime(2026, 1, 1),
      'deletedAt': null,
      'lastEditedAt': null,
      'editHistory': [],
    });
  }

  Future<void> seedCategory() async {
    await firestore.collection('users').doc(_kUid).collection('categories').doc('cat1').set({
      'name': 'Food',
      'type': CategoryType.expense.name,
      'iconKey': 'restaurant',
      'colorValue': 0xFFFF0000,
      'isDefault': false,
      'isActive': true,
      'createdAt': DateTime(2026, 1, 1),
      'deletedAt': null,
      'lastEditedAt': null,
      'editHistory': [],
    });
  }

  Future<void> seedPerson() async {
    await firestore.collection('users').doc(_kUid).collection('people').doc('p1').set({
      'name': 'Rahul Sharma',
      'avatarColorValue': 0xFF000000,
      'openingBalance': 0.0,
      'currentBalance': 0.0,
      'phone': null,
      'email': null,
      'notes': '',
      'createdAt': DateTime(2026, 1, 1),
      'deletedAt': null,
      'lastEditedAt': null,
      'editHistory': [],
    });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> pump(WidgetTester tester) async {
    await seedAccount();
    await seedCategory();
    await seedPerson();

    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _kUid, email: 'test@example.com')),
        ),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    // Resolve the auth stream's first emission before mounting the widget
    // tree — AddExpenseScreen's Person field reads currentUserIdProvider
    // synchronously on first build, which throws if auth hasn't settled yet.
    await container.read(authStateProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AddExpenseScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillBasicFields(WidgetTester tester) async {
    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), '500');
    await tester.pumpAndSettle();
    await tester.enterText(textFields.at(1), 'Lunch');
    await tester.pumpAndSettle();

    // Pick the account chip.
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    // Pick the category via its sheet.
    await tester.tap(find.text('Select a category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
  }

  Future<void> linkPerson(WidgetTester tester) async {
    await tester.tap(find.text('Add a person (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rahul Sharma').last);
    await tester.pumpAndSettle();
  }

  testWidgets('toggle OFF (default): saving creates no Expense, no ledger entry, zero balance change', (tester) async {
    await pump(tester);
    await fillBasicFields(tester);
    await linkPerson(tester);

    // The owed toggle defaults off and is not switched on here.
    final toggle = find.widgetWithText(SwitchListTile, 'This person owes me this expense');
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.ensureVisible(find.text('Save Expense'));
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();

    final expenses = await firestore.collection('users').doc(_kUid).collection('expenses').get();
    expect(expenses.docs, isEmpty);

    final ledger =
        await firestore.collection('users').doc(_kUid).collection('people').doc('p1').collection('ledger').get();
    expect(ledger.docs, isEmpty);

    final person = await firestore.collection('users').doc(_kUid).collection('people').doc('p1').get();
    expect(person.data()!['currentBalance'], 0.0);

    final transactions = await firestore.collection('users').doc(_kUid).collection('transactions').get();
    expect(transactions.docs, hasLength(1));
    expect(transactions.docs.single.data()['linkedPersonId'], 'p1');
    expect(transactions.docs.single.data()['owesPersonToggle'], false);
  });

  testWidgets('toggle ON: saving creates a real Expense + ledger entry, and updates the balance', (tester) async {
    await pump(tester);
    await fillBasicFields(tester);
    await linkPerson(tester);

    await tester.ensureVisible(find.text('This person owes me this expense'));
    await tester.tap(find.text('This person owes me this expense'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save Expense'));
    await tester.tap(find.text('Save Expense'));
    await tester.pumpAndSettle();

    final expenses = await firestore.collection('users').doc(_kUid).collection('expenses').get();
    expect(expenses.docs, hasLength(1));

    final ledger =
        await firestore.collection('users').doc(_kUid).collection('people').doc('p1').collection('ledger').get();
    expect(ledger.docs, hasLength(1));
    expect(ledger.docs.single.data()['type'], 'gave');

    final person = await firestore.collection('users').doc(_kUid).collection('people').doc('p1').get();
    expect(person.data()!['currentBalance'], 500.0);

    final transactions = await firestore.collection('users').doc(_kUid).collection('transactions').get();
    expect(transactions.docs, hasLength(1));
    expect(transactions.docs.single.data()['owesPersonToggle'], true);
  });
}
