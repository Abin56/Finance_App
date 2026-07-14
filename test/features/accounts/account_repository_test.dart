import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AccountRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('accounts').withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    repository = AccountRepository(collection);
  });

  group('AccountRepository.createAccount', () {
    test('sets currentBalance to openingBalance', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 500,
        colorValue: 0xFF000000,
      );

      expect(account.currentBalance, 500);
      expect(account.openingBalance, 500);
    });

    test('supports a negative opening balance', () async {
      final account = await repository.createAccount(
        name: 'Credit line',
        type: AccountType.card,
        openingBalance: -200,
        colorValue: 0xFF000000,
      );

      expect(account.currentBalance, -200);
    });
  });

  group('AccountRepository.adjustBalance', () {
    test('applies a positive delta and records an audit entry', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.adjustBalance(account, 250);

      expect(account.currentBalance, 1250);
      expect(account.editHistory, isNotEmpty);
      expect(account.editHistory.last.field, 'currentBalance');
    });

    test('applies a negative delta', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.adjustBalance(account, -300);

      expect(account.currentBalance, 700);
    });

    test('is a no-op for a zero delta (no audit entry recorded)', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.adjustBalance(account, 0);

      expect(account.currentBalance, 1000);
      expect(account.editHistory, isEmpty);
    });

    test('persists the new balance to Firestore, not just the in-memory object', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.adjustBalance(account, 500);

      final reloaded = await repository.getByKey(account.id);
      expect(reloaded?.currentBalance, 1500);
    });
  });

  group('AccountRepository.reconcileBalance', () {
    test('overwrites currentBalance with openingBalance + transactionsTotal when they differ', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );
      // Simulate drift: currentBalance says 1200 but transactions only sum to 100.
      await repository.adjustBalance(account, 200);

      await repository.reconcileBalance(account, 100);

      expect(account.currentBalance, 1100); // openingBalance(1000) + transactionsTotal(100)
    });

    test('is a no-op when the balance already matches', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );
      final historyLengthBefore = account.editHistory.length;

      await repository.reconcileBalance(account, 0);

      expect(account.currentBalance, 1000);
      expect(account.editHistory.length, historyLengthBefore);
    });
  });

  group('AccountRepository.editAccount', () {
    test('updates name/type/colorValue and records an audit entry per changed field', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.editAccount(account, name: 'Main Wallet', type: AccountType.bank);

      expect(account.name, 'Main Wallet');
      expect(account.type, AccountType.bank);
      expect(account.editHistory.length, 2);
    });

    test('does not expose a way to change openingBalance', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.editAccount(account, name: 'Renamed');

      expect(account.openingBalance, 1000);
    });
  });

  group('Soft-delete / restore', () {
    test('soft-deleting an account does not reverse its balance; restoring brings it back', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );
      await repository.adjustBalance(account, 500);

      await repository.softDelete(account);
      expect(account.isDeleted, isTrue);
      expect(account.currentBalance, 1500);

      final trashed = await repository.getTrash();
      expect(trashed.map((a) => a.id), contains(account.id));

      await repository.restore(account);
      expect(account.isDeleted, isFalse);

      final active = await repository.getAll();
      expect(active.map((a) => a.id), contains(account.id));
    });
  });
}
