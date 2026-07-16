import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Transaction.signedAmount', () {
    test('is positive for income', () {
      final transaction = Transaction(
        id: 't1',
        type: TransactionType.income,
        amount: 100,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(transaction.signedAmount, 100);
    });

    test('is negative for expense', () {
      final transaction = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 100,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(transaction.signedAmount, -100);
    });
  });

  group('Transaction.effectiveMonth', () {
    test('returns dateTime\'s month when accountingMonth is null', () {
      final transaction = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 100,
        dateTime: DateTime(2026, 7, 25),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 7, 25),
      );
      expect(transaction.effectiveMonth, DateTime(2026, 7));
    });

    test('returns accountingMonth when set, ignoring the real date', () {
      final transaction = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 100,
        dateTime: DateTime(2026, 7, 25),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 7, 25),
        accountingMonth: DateTime(2026, 8),
      );
      expect(transaction.effectiveMonth, DateTime(2026, 8));
    });
  });

  group('Transaction.balanceEffect', () {
    test('equals signedAmount when not excluded', () {
      final transaction = Transaction(
        id: 't1',
        type: TransactionType.income,
        amount: 100,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(transaction.balanceEffect, transaction.signedAmount);
    });

    test('is zero when excludeFromCalculations is true, regardless of amount/type', () {
      final expense = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 500,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
        excludeFromCalculations: true,
      );
      final income = Transaction(
        id: 't2',
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
        excludeFromCalculations: true,
      );
      expect(expense.balanceEffect, 0);
      expect(income.balanceEffect, 0);
    });
  });

  group('Transaction Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every field', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          );

      final original = Transaction(
        id: 'ignored-by-doc-id',
        type: TransactionType.expense,
        amount: 49.99,
        dateTime: DateTime(2026, 3, 14, 9, 30),
        accountId: 'acc-1',
        categoryId: 'cat-1',
        notes: 'Coffee',
        createdAt: DateTime(2026, 3, 14, 9, 30),
      );

      await collection.doc('t1').set(original);
      final snapshot = await collection.doc('t1').get();
      final restored = snapshot.data()!;

      expect(restored.id, 't1');
      expect(restored.type, TransactionType.expense);
      expect(restored.amount, 49.99);
      expect(restored.dateTime, DateTime(2026, 3, 14, 9, 30));
      expect(restored.accountId, 'acc-1');
      expect(restored.categoryId, 'cat-1');
      expect(restored.notes, 'Coffee');
      expect(restored.isDeleted, isFalse);
      expect(restored.receiptPurpose, isNull);
    });

    test('preserves a non-null receiptPurpose', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          );

      final original = Transaction(
        id: 't1',
        type: TransactionType.income,
        amount: 500,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
        receiptPurpose: 'splitExpenseSettlement',
      );

      await collection.doc('t1').set(original);
      final restored = (await collection.doc('t1').get()).data()!;

      expect(restored.receiptPurpose, 'splitExpenseSettlement');
    });

    test('preserves a non-null transferId and reports isTransfer', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          );

      final original = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
        transferId: 'transfer-1',
      );

      await collection.doc('t1').set(original);
      final restored = (await collection.doc('t1').get()).data()!;

      expect(restored.transferId, 'transfer-1');
      expect(restored.isTransfer, isTrue);
    });

    test('defaults transferId to null and isTransfer to false for a normal transaction', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          );

      final original = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('t1').set(original);
      final restored = (await collection.doc('t1').get()).data()!;

      expect(restored.transferId, isNull);
      expect(restored.isTransfer, isFalse);
    });

    test('preserves excludeFromCalculations and accountingMonth', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          );

      final original = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 7, 25),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 7, 25),
        excludeFromCalculations: true,
        accountingMonth: DateTime(2026, 8),
      );

      await collection.doc('t1').set(original);
      final restored = (await collection.doc('t1').get()).data()!;

      expect(restored.excludeFromCalculations, isTrue);
      expect(restored.accountingMonth, DateTime(2026, 8));
    });

    test('defaults excludeFromCalculations to false and accountingMonth to null', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          );

      final original = Transaction(
        id: 't1',
        type: TransactionType.expense,
        amount: 300,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('t1').set(original);
      final restored = (await collection.doc('t1').get()).data()!;

      expect(restored.excludeFromCalculations, isFalse);
      expect(restored.accountingMonth, isNull);
    });

    test('preserves audit trail and soft-delete state', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('transactions').withConverter<Transaction>(
            fromFirestore: Transaction.fromFirestore,
            toFirestore: (t, _) => t.toFirestore(),
          );

      final transaction = Transaction(
        id: 't1',
        type: TransactionType.income,
        amount: 10,
        dateTime: DateTime(2026, 1, 1),
        accountId: 'a1',
        categoryId: 'c1',
        createdAt: DateTime(2026, 1, 1),
      );
      transaction.recordEdit(field: 'amount', oldValue: '10', newValue: '20');
      transaction.amount = 20;
      transaction.markDeleted();

      await collection.doc('t1').set(transaction);
      final restored = (await collection.doc('t1').get()).data()!;

      expect(restored.amount, 20);
      expect(restored.editHistory, hasLength(1));
      expect(restored.editHistory.first.field, 'amount');
      expect(restored.isDeleted, isTrue);
    });
  });
}
