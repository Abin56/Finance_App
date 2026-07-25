import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence.dart';
import 'package:finance_app/features/bills/domain/bill_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BillOccurrence makeOccurrence({
    double amount = 100,
    DateTime? dueDate,
    double amountPaid = 0,
    bool isSkipped = false,
  }) {
    return BillOccurrence(
      id: 'o1',
      billId: 'b1',
      dueDate: dueDate ?? DateTime.now(),
      amount: amount,
      createdAt: DateTime(2026, 1, 1),
      amountPaid: amountPaid,
      isSkipped: isSkipped,
    );
  }

  group('BillOccurrence.status', () {
    test('is paid once amountPaid reaches amount', () {
      expect(makeOccurrence(amount: 100, amountPaid: 100).status, BillStatus.paid);
    });

    test('is paid even if amountPaid exceeds amount (overshoot)', () {
      expect(makeOccurrence(amount: 100, amountPaid: 120).status, BillStatus.paid);
    });

    test('is skipped when isSkipped is true and not fully paid', () {
      expect(makeOccurrence(amount: 100, amountPaid: 0, isSkipped: true).status, BillStatus.skipped);
    });

    test('is partiallyPaid when 0 < amountPaid < amount', () {
      expect(makeOccurrence(amount: 100, amountPaid: 40).status, BillStatus.partiallyPaid);
    });

    test('is overdue when due date is before today and nothing paid', () {
      final due = DateTime.now().subtract(const Duration(days: 2));
      expect(makeOccurrence(dueDate: due).status, BillStatus.overdue);
    });

    test('is dueToday when due date is today', () {
      expect(makeOccurrence(dueDate: DateTime.now()).status, BillStatus.dueToday);
    });

    test('is upcoming when due date is after today', () {
      final due = DateTime.now().add(const Duration(days: 5));
      expect(makeOccurrence(dueDate: due).status, BillStatus.upcoming);
    });
  });

  group('BillOccurrence.remainingAmount', () {
    test('is amount minus amountPaid', () {
      expect(makeOccurrence(amount: 100, amountPaid: 30).remainingAmount, 70);
    });

    test('clamps to 0 when amountPaid exceeds amount', () {
      expect(makeOccurrence(amount: 100, amountPaid: 150).remainingAmount, 0);
    });
  });

  group('BillOccurrence Firestore round-trip', () {
    test('toFirestore/fromFirestore preserves every field', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('occurrences').withConverter<BillOccurrence>(
            fromFirestore: BillOccurrence.fromFirestore,
            toFirestore: (o, _) => o.toFirestore(),
          );

      final original = BillOccurrence(
        id: 'ignored',
        billId: 'b1',
        dueDate: DateTime(2026, 4, 1),
        amount: 25000,
        amountPaid: 5000,
        createdAt: DateTime(2026, 1, 1),
      );

      await collection.doc('occ-1').set(original);
      final restored = (await collection.doc('occ-1').get()).data()!;

      expect(restored.id, 'occ-1');
      expect(restored.billId, 'b1');
      expect(restored.dueDate, DateTime(2026, 4, 1));
      expect(restored.amount, 25000);
      expect(restored.amountPaid, 5000);
      expect(restored.isSkipped, isFalse);
      expect(restored.isDeleted, isFalse);
    });

    test('preserves audit trail and soft-delete state', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('occurrences').withConverter<BillOccurrence>(
            fromFirestore: BillOccurrence.fromFirestore,
            toFirestore: (o, _) => o.toFirestore(),
          );

      final occurrence = BillOccurrence(
        id: 'ignored',
        billId: 'b1',
        dueDate: DateTime(2026, 2, 1),
        amount: 1000,
        createdAt: DateTime(2026, 1, 1),
      );
      occurrence.recordEdit(field: 'amountPaid', oldValue: '0', newValue: '1000');
      occurrence.markDeleted();

      await collection.doc('occ-2').set(occurrence);
      final restored = (await collection.doc('occ-2').get()).data()!;

      expect(restored.editHistory, hasLength(1));
      expect(restored.editHistory.first.field, 'amountPaid');
      expect(restored.isDeleted, isTrue);
    });
  });
}
