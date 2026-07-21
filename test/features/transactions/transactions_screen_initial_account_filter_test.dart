import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/domain/category.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/people/presentation/providers/people_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:finance_app/features/transactions/presentation/screens/transactions_screen.dart';

/// Regression test for Account Details' "View Full History" entry point —
/// `TransactionsScreen(initialAccountId: ...)` must show only that
/// account's transactions on open, exactly as if the user had opened
/// Filters and picked the account manually (see `_filter` init in
/// `transactions_screen.dart`).
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  final accountA = Account(
    id: 'accA',
    name: 'Cash',
    type: AccountType.cash,
    openingBalance: 0,
    currentBalance: 0,
    colorValue: 0xFF00FF00,
    createdAt: DateTime(2026, 1, 1),
  );
  final accountB = Account(
    id: 'accB',
    name: 'Bank',
    type: AccountType.bank,
    openingBalance: 0,
    currentBalance: 0,
    colorValue: 0xFF0000FF,
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

  Transaction transactionFor(String id, String accountId, String notes) {
    return Transaction(
      id: id,
      type: TransactionType.expense,
      amount: 100,
      dateTime: DateTime(2026, 6, 1),
      accountId: accountId,
      categoryId: category.id,
      notes: notes,
      createdAt: DateTime(2026, 6, 1),
    );
  }

  /// `TransactionsScreen` watches `transactionRepositoryProvider` directly
  /// (for the swipe-to-trash `Dismissible`), so it must resolve to a real
  /// repository even though the transaction *list* itself comes from the
  /// overridden [transactionsStreamProvider] below — building one against a
  /// throwaway `FakeFirebaseFirestore` sidesteps the auth-state dependency
  /// entirely rather than standing up `MockFirebaseAuth` for a screen that
  /// never reads the signed-in user here.
  TransactionRepository fakeTransactionRepository() {
    final firestore = FakeFirebaseFirestore();
    final accountCollection = firestore.collection('accounts').withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    final transactionCollection = firestore.collection('transactions').withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    return TransactionRepository(transactionCollection, AccountRepository(accountCollection));
  }

  testWidgets('shows only the pre-selected account\'s transactions, hiding other accounts\'', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(fakeTransactionRepository()),
          accountsStreamProvider.overrideWith((ref) => Stream.value([accountA, accountB])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([category])),
          peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
          smsPendingCountProvider.overrideWithValue(0),
          transactionsStreamProvider.overrideWith(
            (ref) => Stream.value([
              transactionFor('t1', accountA.id, 'Coffee in Cash'),
              transactionFor('t2', accountB.id, 'Groceries in Bank'),
            ]),
          ),
        ],
        child: MaterialApp(home: TransactionsScreen(initialAccountId: accountA.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee in Cash'), findsOneWidget);
    expect(find.text('Groceries in Bank'), findsNothing);
  });

  testWidgets('with no initialAccountId, both accounts\' transactions show', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(fakeTransactionRepository()),
          accountsStreamProvider.overrideWith((ref) => Stream.value([accountA, accountB])),
          categoriesStreamProvider.overrideWith((ref) => Stream.value([category])),
          peopleStreamProvider.overrideWith((ref) => Stream.value(const [])),
          smsPendingCountProvider.overrideWithValue(0),
          transactionsStreamProvider.overrideWith(
            (ref) => Stream.value([
              transactionFor('t1', accountA.id, 'Coffee in Cash'),
              transactionFor('t2', accountB.id, 'Groceries in Bank'),
            ]),
          ),
        ],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee in Cash'), findsOneWidget);
    expect(find.text('Groceries in Bank'), findsOneWidget);
  });
}
