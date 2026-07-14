import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/bill_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill makeBill({
    double amount = 100,
    DateTime? dueDate,
    double amountPaid = 0,
    bool isSkipped = false,
  }) {
    return Bill(
      id: 'b1',
      name: 'Electricity',
      amount: amount,
      dueDate: dueDate ?? DateTime.now(),
      recurrence: BillRecurrence.monthly,
      createdAt: DateTime(2026, 1, 1),
      amountPaid: amountPaid,
      isSkipped: isSkipped,
    );
  }

  group('Bill.status', () {
    test('is paid once amountPaid reaches amount', () {
      expect(makeBill(amount: 100, amountPaid: 100).status, BillStatus.paid);
    });

    test('is paid even if amountPaid exceeds amount (overshoot)', () {
      expect(makeBill(amount: 100, amountPaid: 120).status, BillStatus.paid);
    });

    test('is skipped when isSkipped is true and not fully paid', () {
      expect(makeBill(amount: 100, amountPaid: 0, isSkipped: true).status, BillStatus.skipped);
    });

    test('is partiallyPaid when 0 < amountPaid < amount', () {
      expect(makeBill(amount: 100, amountPaid: 40).status, BillStatus.partiallyPaid);
    });

    test('is overdue when due date is before today and nothing paid', () {
      final due = DateTime.now().subtract(const Duration(days: 2));
      expect(makeBill(dueDate: due).status, BillStatus.overdue);
    });

    test('is dueToday when due date is today', () {
      expect(makeBill(dueDate: DateTime.now()).status, BillStatus.dueToday);
    });

    test('is upcoming when due date is after today', () {
      final due = DateTime.now().add(const Duration(days: 5));
      expect(makeBill(dueDate: due).status, BillStatus.upcoming);
    });
  });

  group('Bill.remainingAmount', () {
    test('is amount minus amountPaid', () {
      expect(makeBill(amount: 100, amountPaid: 30).remainingAmount, 70);
    });

    test('clamps to 0 when amountPaid exceeds amount', () {
      expect(makeBill(amount: 100, amountPaid: 150).remainingAmount, 0);
    });
  });

  group('Bill Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every field for a recurring bill', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('bills').withConverter<Bill>(
            fromFirestore: Bill.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );

      final original = Bill(
        id: 'ignored',
        name: 'Rent',
        amount: 25000,
        dueDate: DateTime(2026, 4, 1),
        recurrence: BillRecurrence.custom,
        customIntervalDays: 45,
        accountId: 'acc-1',
        categoryId: 'cat-1',
        reminderOffsets: const [0, 1, 7],
        notes: 'Pay via bank transfer',
        amountPaid: 5000,
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('bill-1').set(original);
      final restored = (await collection.doc('bill-1').get()).data()!;

      expect(restored.id, 'bill-1');
      expect(restored.name, 'Rent');
      expect(restored.amount, 25000);
      expect(restored.dueDate, DateTime(2026, 4, 1));
      expect(restored.recurrence, BillRecurrence.custom);
      expect(restored.customIntervalDays, 45);
      expect(restored.accountId, 'acc-1');
      expect(restored.categoryId, 'cat-1');
      expect(restored.reminderOffsets, [0, 1, 7]);
      expect(restored.notes, 'Pay via bank transfer');
      expect(restored.amountPaid, 5000);
      expect(restored.isSkipped, isFalse);
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
        dueDate: DateTime(2026, 2, 1),
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
  });
}
