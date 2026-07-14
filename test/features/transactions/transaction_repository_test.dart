import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AccountRepository accountRepository;
  late TransactionRepository transactionRepository;

  setUp(() {
    firestore = FakeFirebaseFirestore();

    final accountsCollection = firestore.collection('accounts').withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    accountRepository = AccountRepository(accountsCollection);

    final transactionsCollection = firestore.collection('transactions').withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    transactionRepository = TransactionRepository(transactionsCollection, accountRepository);
  });

  Future<Account> seedAccount({String name = 'Wallet', double openingBalance = 1000}) {
    return accountRepository.createAccount(
      name: name,
      type: AccountType.cash,
      openingBalance: openingBalance,
      colorValue: 0xFF5B5FEF,
    );
  }

  group('TransactionRepository balance sync', () {
    test('createTransaction increases balance for income', () async {
      final account = await seedAccount();

      await transactionRepository.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
      );

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1500);
    });

    test('createTransaction decreases balance for expense', () async {
      final account = await seedAccount();

      await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 200,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
      );

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 800);
    });

    test('editTransaction applies the net delta when the account is unchanged', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 200,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
      );
      // Balance is now 800. Bump the expense to 300 — balance should drop
      // by the extra 100, landing at 700, not be recomputed from scratch.
      await transactionRepository.editTransaction(transaction, amount: 300);

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 700);
    });

    test('editTransaction moves the balance effect when the account changes', () async {
      final accountA = await seedAccount(name: 'A', openingBalance: 1000);
      final accountB = await seedAccount(name: 'B', openingBalance: 1000);
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 100,
        dateTime: DateTime(2026, 1, 1),
        accountId: accountA.id,
        categoryId: 'cat-1',
      );
      // accountA is now 900. Move the transaction to accountB entirely.
      await transactionRepository.editTransaction(transaction, accountId: accountB.id);

      final updatedA = await accountRepository.getByKey(accountA.id);
      final updatedB = await accountRepository.getByKey(accountB.id);
      expect(updatedA!.currentBalance, 1000, reason: 'old account balance fully reversed');
      expect(updatedB!.currentBalance, 900, reason: 'new account balance fully applied');
    });

    test('softDeleteTransaction reverses the balance effect', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.income,
        amount: 250,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
      );

      await transactionRepository.softDeleteTransaction(transaction);

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1000);
      expect(transaction.isDeleted, isTrue);
    });

    test('restoreTransaction re-applies the balance effect', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.income,
        amount: 250,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
      );
      await transactionRepository.softDeleteTransaction(transaction);

      await transactionRepository.restoreTransaction(transaction);

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1250);
      expect(transaction.isDeleted, isFalse);
    });

    test('permanentlyDeleteTransaction does not change the balance again', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.income,
        amount: 250,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
      );
      await transactionRepository.softDeleteTransaction(transaction);

      await transactionRepository.permanentlyDeleteTransaction(transaction);

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1000);
      expect(await transactionRepository.getByKey(transaction.id), isNull);
    });
  });
}
