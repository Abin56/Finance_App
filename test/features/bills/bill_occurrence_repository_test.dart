import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/bills/data/bill_occurrence_repository.dart';
import 'package:finance_app/features/bills/data/bill_repository.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/payment_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BillRepository billRepository;
  late BillOccurrenceRepository repository;

  Bill makeBill({
    String id = 'bill1',
    BillRecurrence recurrence = BillRecurrence.monthly,
    DateTime? nextDueDate,
    double amount = 100,
  }) {
    return Bill(
      id: id,
      name: 'Electricity',
      amount: amount,
      nextDueDate: nextDueDate ?? DateTime(2026, 3, 10),
      recurrence: recurrence,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final billCollection = firestore.collection('bills').withConverter<Bill>(
          fromFirestore: Bill.fromFirestore,
          toFirestore: (b, _) => b.toFirestore(),
        );
    billRepository = BillRepository(billCollection);

    final occurrenceCollection = firestore
        .collection('bills')
        .doc('bill1')
        .collection('occurrences')
        .withConverter<BillOccurrence>(
          fromFirestore: BillOccurrence.fromFirestore,
          toFirestore: (o, _) => o.toFirestore(),
        );
    repository = BillOccurrenceRepository(
      occurrenceCollection,
      billRepository,
      firestore.collection('bills').doc('bill1'),
      firestore.collection('bills').doc('bill1').collection('payments'),
    );
  });

  group('BillOccurrenceRepository.ensureCurrentOccurrence — fresh bill', () {
    test('materializes a fresh occurrence at nextDueDate when none exists and no legacy state', () async {
      final bill = makeBill(nextDueDate: DateTime(2026, 3, 10), amount: 500);
      await billRepository.add(bill.id, bill);

      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      expect(occurrence.dueDate, DateTime(2026, 3, 10));
      expect(occurrence.amount, 500);
      expect(occurrence.amountPaid, 0);
      expect(occurrence.isSkipped, isFalse);
    });

    test('is idempotent — a second call for the same bill returns the same occurrence', () async {
      final bill = makeBill();
      await billRepository.add(bill.id, bill);

      final first = await repository.ensureCurrentOccurrence(bill, const []);
      final existing = await repository.getAll();
      final second = await repository.ensureCurrentOccurrence(bill, existing);

      expect(second.id, first.id);
      final all = await repository.getAll();
      expect(all, hasLength(1), reason: 'a second call must not materialize a duplicate occurrence');
    });
  });

  group('BillOccurrenceRepository.ensureCurrentOccurrence — legacy adoption', () {
    test('adopts a pre-migration bill\'s in-progress amountPaid/isSkipped into one occurrence', () async {
      final bill = makeBill(nextDueDate: DateTime(2026, 3, 10), amount: 1000);
      await billRepository.add(bill.id, bill);
      // Simulate legacy raw fields still present on the Bill document from
      // before this migration (amountPaid/isSkipped no longer parsed by
      // Bill.fromFirestore, but still physically on the document).
      await firestore.collection('bills').doc('bill1').update({'amountPaid': 400, 'isSkipped': false});

      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      expect(occurrence.dueDate, DateTime(2026, 3, 10));
      expect(occurrence.amount, 1000);
      expect(occurrence.amountPaid, 400);
    });

    test('adoption backfills every existing PaymentRecord\'s occurrenceId', () async {
      final bill = makeBill(amount: 1000);
      await billRepository.add(bill.id, bill);
      await firestore.collection('bills').doc('bill1').update({'amountPaid': 400});

      final payment = PaymentRecord(
        id: 'p1',
        billId: 'bill1',
        amount: 400,
        date: DateTime(2026, 3, 1),
        createdAt: DateTime(2026, 3, 1),
      );
      final paymentsCollection = firestore.collection('bills').doc('bill1').collection('payments').withConverter<PaymentRecord>(
            fromFirestore: PaymentRecord.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          );
      await paymentsCollection.doc(payment.id).set(payment);

      final occurrence = await repository.ensureCurrentOccurrence(bill, const [], legacyPayments: [payment]);

      final backfilled = (await paymentsCollection.doc('p1').get()).data()!;
      expect(backfilled.occurrenceId, occurrence.id);
    });

    test('adoption never fires twice — a legacy bill only ever gets one adopted occurrence', () async {
      final bill = makeBill(amount: 1000);
      await billRepository.add(bill.id, bill);
      await firestore.collection('bills').doc('bill1').update({'amountPaid': 400});

      final first = await repository.ensureCurrentOccurrence(bill, const []);
      final existing = await repository.getAll();
      // Legacy state is still physically present on the document (adoption
      // doesn't strip it), but "existing is non-empty" must still guard a
      // second adoption from ever happening.
      final second = await repository.ensureCurrentOccurrence(bill, existing);

      expect(second.id, first.id);
      final all = await repository.getAll();
      expect(all, hasLength(1));
    });

    test('adopts based on existing PaymentRecords even if amountPaid/isSkipped are both absent', () async {
      final bill = makeBill(amount: 1000);
      await billRepository.add(bill.id, bill);
      final payment = PaymentRecord(
        id: 'p1',
        billId: 'bill1',
        amount: 300,
        date: DateTime(2026, 3, 1),
        createdAt: DateTime(2026, 3, 1),
      );
      final paymentsCollection = firestore.collection('bills').doc('bill1').collection('payments').withConverter<PaymentRecord>(
            fromFirestore: PaymentRecord.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          );
      await paymentsCollection.doc(payment.id).set(payment);

      final occurrence = await repository.ensureCurrentOccurrence(bill, const [], legacyPayments: [payment]);

      expect(occurrence.dueDate, bill.nextDueDate);
    });
  });

  group('BillOccurrenceRepository.ensureCurrentOccurrence — rollover', () {
    test('rolls a settled recurring occurrence forward and advances the template\'s nextDueDate', () async {
      final bill = makeBill(nextDueDate: DateTime(2026, 3, 10), recurrence: BillRecurrence.monthly, amount: 100);
      await billRepository.add(bill.id, bill);

      final first = await repository.ensureCurrentOccurrence(bill, const []);
      await repository.markPaid(first);

      final existing = await repository.getAll();
      final next = await repository.ensureCurrentOccurrence(bill, existing);

      expect(next.id, isNot(first.id));
      expect(next.dueDate, DateTime(2026, 4, 10));
      expect(bill.nextDueDate, DateTime(2026, 4, 10));
    });

    test('does not roll a settled one-time occurrence forward', () async {
      final bill = makeBill(nextDueDate: DateTime(2026, 3, 10), recurrence: BillRecurrence.oneTime, amount: 100);
      await billRepository.add(bill.id, bill);

      final first = await repository.ensureCurrentOccurrence(bill, const []);
      await repository.markPaid(first);

      final existing = await repository.getAll();
      final result = await repository.ensureCurrentOccurrence(bill, existing);

      expect(result.id, first.id);
      final all = await repository.getAll();
      expect(all, hasLength(1));
    });
  });

  group('BillOccurrenceRepository.applyPayment', () {
    test('accumulates a partial payment', () async {
      final bill = makeBill(amount: 100);
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.applyPayment(occurrence, 40);
      expect(occurrence.amountPaid, 40);
    });

    test('clamps at the occurrence amount without touching it again once settled', () async {
      final bill = makeBill(amount: 100);
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.applyPayment(occurrence, 40);
      await repository.applyPayment(occurrence, 90);

      expect(occurrence.amountPaid, 100);
    });

    test('is a no-op for a zero delta', () async {
      final bill = makeBill();
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.applyPayment(occurrence, 0);
      expect(occurrence.editHistory, isEmpty);
    });
  });

  group('BillOccurrenceRepository.markPaid', () {
    test('sets amountPaid to the full amount', () async {
      final bill = makeBill(recurrence: BillRecurrence.oneTime, amount: 250);
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.markPaid(occurrence);
      expect(occurrence.amountPaid, 250);
    });

    test('is a no-op when already fully paid', () async {
      final bill = makeBill(recurrence: BillRecurrence.oneTime, amount: 250);
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.markPaid(occurrence);
      final historyLengthAfterFirst = occurrence.editHistory.length;

      await repository.markPaid(occurrence);
      expect(occurrence.editHistory.length, historyLengthAfterFirst);
    });
  });

  group('BillOccurrenceRepository.skipOccurrence / unskip', () {
    test('skipOccurrence marks isSkipped without mutating dueDate', () async {
      final bill = makeBill(nextDueDate: DateTime(2026, 3, 10));
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.skipOccurrence(occurrence);

      expect(occurrence.isSkipped, isTrue);
      expect(occurrence.dueDate, DateTime(2026, 3, 10));
    });

    test('unskip reverses isSkipped', () async {
      final bill = makeBill();
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.skipOccurrence(occurrence);
      await repository.unskip(occurrence);

      expect(occurrence.isSkipped, isFalse);
    });

    test('unskip is a no-op when not skipped', () async {
      final bill = makeBill();
      await billRepository.add(bill.id, bill);
      final occurrence = await repository.ensureCurrentOccurrence(bill, const []);

      await repository.unskip(occurrence);
      expect(occurrence.editHistory, isEmpty);
    });
  });
}
