import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/budget/presentation/providers/budget_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Provider-level tests proving `excludeFromCalculations`/`accountingMonth`
/// are respected by the Budget cards — each test seeds fixtures through the
/// real repositories (same path the app takes) and asserts on the composed
/// provider's output.
void main() {
  late ProviderContainer container;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
  });

  Future<String> seedAccount() async {
    final account = await container.read(accountRepositoryProvider).createAccount(
          name: 'Wallet',
          type: AccountType.cash,
          openingBalance: 10000,
          colorValue: 0xFF000000,
        );
    return account.id;
  }

  group('monthSpentProvider', () {
    test('excludes a transaction marked excludeFromCalculations', () async {
      final now = DateTime.now();
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: now,
        accountId: accountId,
        categoryId: 'groceries',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: now,
        accountId: accountId,
        categoryId: 'reimbursable',
        excludeFromCalculations: true,
      );

      await container.read(transactionsStreamProvider.future);

      expect(container.read(monthSpentProvider(now)), 500, reason: 'excluded transaction must not count');
    });

    test('a transaction assigned to next month via accountingMonth counts toward next month, not this one', () async {
      final now = DateTime.now();
      final nextMonth = DateTime(now.year, now.month + 1);
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 400,
        dateTime: now,
        accountId: accountId,
        categoryId: 'advance-payment',
        accountingMonth: nextMonth,
      );

      await container.read(transactionsStreamProvider.future);

      expect(container.read(monthSpentProvider(now)), 0, reason: 'reassigned away from this month');
      expect(container.read(monthSpentProvider(nextMonth)), 400, reason: 'must count toward its accounting month');
    });
  });

  group('categorySpentProvider', () {
    test('excludes a transaction marked excludeFromCalculations from its category total', () async {
      final now = DateTime.now();
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 200,
        dateTime: now,
        accountId: accountId,
        categoryId: 'groceries',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 150,
        dateTime: now,
        accountId: accountId,
        categoryId: 'groceries',
        excludeFromCalculations: true,
      );

      await container.read(transactionsStreamProvider.future);

      expect(container.read(categorySpentProvider('groceries')), 200);
    });
  });

  group('todaySpentProvider', () {
    test('excludes a transaction marked excludeFromCalculations', () async {
      final now = DateTime.now();
      final accountId = await seedAccount();
      final transactions = container.read(transactionRepositoryProvider);

      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 100,
        dateTime: now,
        accountId: accountId,
        categoryId: 'lunch',
      );
      await transactions.createTransaction(
        type: TransactionType.expense,
        amount: 50,
        dateTime: now,
        accountId: accountId,
        categoryId: 'lunch',
        excludeFromCalculations: true,
      );

      await container.read(transactionsStreamProvider.future);

      expect(container.read(todaySpentProvider), 100);
    });
  });
}
