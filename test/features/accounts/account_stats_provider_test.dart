import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_stats_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for `accountStatsProvider` — Account Details' stats section.
/// Only Income/Expense/Transfers In/Transfers Out/currentMonthExpense are
/// computed (see the provider's doc comment for why Credit Card
/// Payments/Bills Paid etc. are deliberately not inferred yet).
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

  Future<String> createAccount(String name) async {
    final accounts = container.read(accountRepositoryProvider);
    final account = await accounts.createAccount(
      name: name,
      type: AccountType.bank,
      openingBalance: 0,
      colorValue: 0xFF000000,
    );
    return account.id;
  }

  test('sums income and expense for the given account only, ignoring other accounts', () async {
    final accountA = await createAccount('A');
    final accountB = await createAccount('B');

    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.income,
      amount: 5000,
      dateTime: DateTime.now(),
      accountId: accountA,
      categoryId: 'salary',
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 1200,
      dateTime: DateTime.now(),
      accountId: accountA,
      categoryId: 'food',
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 999,
      dateTime: DateTime.now(),
      accountId: accountB,
      categoryId: 'food',
    );

    await container.read(transactionsStreamProvider.future);

    final stats = container.read(accountStatsProvider(accountA));
    expect(stats.income, 5000);
    expect(stats.expense, 1200);
  });

  test('a transfer pair counts as transfersOut on the source and transfersIn on the destination', () async {
    final source = await createAccount('Source');
    final destination = await createAccount('Destination');

    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransferPair(
      amount: 2000,
      dateTime: DateTime.now(),
      sourceAccountId: source,
      destinationAccountId: destination,
      categoryId: 'transfer',
    );

    await container.read(transactionsStreamProvider.future);

    final sourceStats = container.read(accountStatsProvider(source));
    expect(sourceStats.transfersOut, 2000);
    expect(sourceStats.transfersIn, 0);
    expect(sourceStats.expense, 0, reason: 'a transfer leg must never count as a plain expense');

    final destinationStats = container.read(accountStatsProvider(destination));
    expect(destinationStats.transfersIn, 2000);
    expect(destinationStats.transfersOut, 0);
    expect(destinationStats.income, 0, reason: 'a transfer leg must never count as plain income');
  });

  test('currentMonthExpense only sums expenses dated in the current calendar month', () async {
    final accountId = await createAccount('A');
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15);

    final transactions = container.read(transactionRepositoryProvider);
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 300,
      dateTime: now,
      accountId: accountId,
      categoryId: 'food',
    );
    await transactions.createTransaction(
      type: TransactionType.expense,
      amount: 700,
      dateTime: lastMonth,
      accountId: accountId,
      categoryId: 'food',
    );

    await container.read(transactionsStreamProvider.future);

    final stats = container.read(accountStatsProvider(accountId));
    expect(stats.currentMonthExpense, 300);
    expect(stats.expense, 1000, reason: 'total expense still includes both months');
  });
}
