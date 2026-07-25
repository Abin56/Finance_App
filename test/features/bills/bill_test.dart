import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bill Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every template field for a recurring bill', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('bills').withConverter<Bill>(
            fromFirestore: Bill.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );

      final original = Bill(
        id: 'ignored',
        name: 'Rent',
        amount: 25000,
        nextDueDate: DateTime(2026, 4, 1),
        recurrence: BillRecurrence.custom,
        customIntervalDays: 45,
        accountId: 'acc-1',
        categoryId: 'cat-1',
        reminderOffsets: const [0, 1, 7],
        notes: 'Pay via bank transfer',
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('bill-1').set(original);
      final restored = (await collection.doc('bill-1').get()).data()!;

      expect(restored.id, 'bill-1');
      expect(restored.name, 'Rent');
      expect(restored.amount, 25000);
      expect(restored.nextDueDate, DateTime(2026, 4, 1));
      expect(restored.recurrence, BillRecurrence.custom);
      expect(restored.customIntervalDays, 45);
      expect(restored.accountId, 'acc-1');
      expect(restored.categoryId, 'cat-1');
      expect(restored.reminderOffsets, [0, 1, 7]);
      expect(restored.notes, 'Pay via bank transfer');
      expect(restored.isDeleted, isFalse);
    });

    test('preserves audit trail and soft-delete state', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('bills').withConverter<Bill>(
            fromFirestore: Bill.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );

      final bill = Bill(
        id: 'ignored',
        name: 'Internet',
        amount: 1000,
        nextDueDate: DateTime(2026, 2, 1),
        recurrence: BillRecurrence.monthly,
        createdAt: DateTime(2026, 1, 1),
      );
      bill.recordEdit(field: 'amount', oldValue: '900', newValue: '1000');
      bill.markDeleted();

      await collection.doc('bill-2').set(bill);
      final restored = (await collection.doc('bill-2').get()).data()!;

      expect(restored.editHistory, hasLength(1));
      expect(restored.editHistory.first.field, 'amount');
      expect(restored.isDeleted, isTrue);
    });

    test('a legacy document with no nextDueDate field falls back to reading dueDate', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('bills');
      // Simulate a pre-migration document written before `nextDueDate`
      // existed — only the old `dueDate` field is present.
      await collection.doc('legacy-1').set({
        'name': 'Legacy Bill',
        'amount': 500,
        'dueDate': Timestamp.fromDate(DateTime(2026, 3, 15)),
        'recurrence': 'monthly',
        'reminderOffsets': <int>[],
        'notes': '',
        'amountPaid': 200,
        'isSkipped': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      final typed = firestore.collection('bills').withConverter<Bill>(
            fromFirestore: Bill.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );
      final restored = (await typed.doc('legacy-1').get()).data()!;

      expect(restored.nextDueDate, DateTime(2026, 3, 15));
    });
  });
}
