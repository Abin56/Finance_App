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

  group('TransactionRepository — excludeFromCalculations', () {
    test('createTransaction with excludeFromCalculations=true does not change the balance', () async {
      final account = await seedAccount();

      await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
        excludeFromCalculations: true,
      );

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1000, reason: 'excluded expense must not affect balance');
    });

    test('createTransaction with excludeFromCalculations=true does not change balance for income either', () async {
      final account = await seedAccount();

      await transactionRepository.createTransaction(
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
        excludeFromCalculations: true,
      );

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1000, reason: 'excluded income must not affect balance');
    });

    test('editTransaction toggling excludeFromCalculations to true reverses the balance effect', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
      );
      // Balance is now 700.
      await transactionRepository.editTransaction(transaction, excludeFromCalculations: true);

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1000, reason: 'toggling exclude on must reverse the prior balance effect');
    });

    test('editTransaction toggling excludeFromCalculations back to false re-applies the balance effect', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
        excludeFromCalculations: true,
      );
      // Balance is still 1000 (excluded on create).
      await transactionRepository.editTransaction(transaction, excludeFromCalculations: false);

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 700, reason: 'toggling exclude off must apply the balance effect');
    });

    test('editTransaction amount change while excluded does not affect balance', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 1, 1),
        accountId: account.id,
        categoryId: 'cat-1',
        excludeFromCalculations: true,
      );

      await transactionRepository.editTransaction(transaction, amount: 900);

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 1000, reason: 'amount changes on an excluded transaction stay balance-neutral');
    });
  });

  group('TransactionRepository — accountingMonth', () {
    test('editTransaction sets accountingMonth', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 100,
        dateTime: DateTime(2026, 7, 25),
        accountId: account.id,
        categoryId: 'cat-1',
      );

      await transactionRepository.editTransaction(transaction, accountingMonth: DateTime(2026, 8));

      expect(transaction.accountingMonth, DateTime(2026, 8));
      expect(transaction.effectiveMonth, DateTime(2026, 8));
    });

    test('editTransaction clears accountingMonth back to "same as transaction date"', () async {
      final account = await seedAccount();
      final transaction = await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 100,
        dateTime: DateTime(2026, 7, 25),
        accountId: account.id,
        categoryId: 'cat-1',
        accountingMonth: DateTime(2026, 8),
      );

      await transactionRepository.editTransaction(transaction, clearAccountingMonth: true);

      expect(transaction.accountingMonth, isNull);
      expect(transaction.effectiveMonth, DateTime(2026, 7));
    });

    test('accountingMonth never affects balance — it is a reporting-only concern', () async {
      final account = await seedAccount();

      await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 400,
        dateTime: DateTime(2026, 7, 25),
        accountId: account.id,
        categoryId: 'cat-1',
        accountingMonth: DateTime(2026, 8),
      );

      final updated = await accountRepository.getByKey(account.id);
      expect(updated!.currentBalance, 600, reason: 'balance reflects the real transaction, regardless of its accounting month');
    });
  });

  group('TransactionRepository.createTransferPair', () {
    test('moves the balance from source to destination, not net-zero on either', () async {
      final source = await seedAccount(name: 'Source', openingBalance: 1000);
      final destination = await seedAccount(name: 'Destination', openingBalance: 500);

      await transactionRepository.createTransferPair(
        amount: 300,
        dateTime: DateTime(2026, 1, 1),
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        categoryId: 'cat-transfer',
      );

      final updatedSource = await accountRepository.getByKey(source.id);
      final updatedDestination = await accountRepository.getByKey(destination.id);
      expect(updatedSource!.currentBalance, 700);
      expect(updatedDestination!.currentBalance, 800);
    });

    test('both legs share one transferId and are marked isTransfer', () async {
      final source = await seedAccount(name: 'Source');
      final destination = await seedAccount(name: 'Destination');

      final (sourceLeg, destinationLeg) = await transactionRepository.createTransferPair(
        amount: 100,
        dateTime: DateTime(2026, 1, 1),
        sourceAccountId: source.id,
        destinationAccountId: destination.id,
        categoryId: 'cat-transfer',
      );

      expect(sourceLeg.isTransfer, isTrue);
      expect(destinationLeg.isTransfer, isTrue);
      expect(sourceLeg.transferId, destinationLeg.transferId);
      expect(sourceLeg.type, TransactionType.expense);
      expect(destinationLeg.type, TransactionType.income);
    });

    test('rejects transferring an account to itself', () async {
      final account = await seedAccount();

      expect(
        () => transactionRepository.createTransferPair(
          amount: 100,
          dateTime: DateTime(2026, 1, 1),
          sourceAccountId: account.id,
          destinationAccountId: account.id,
          categoryId: 'cat-transfer',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
