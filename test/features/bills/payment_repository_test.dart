import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/bills/data/bill_occurrence_repository.dart';
import 'package:finance_app/features/bills/data/bill_repository.dart';
import 'package:finance_app/features/bills/data/payment_repository.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_occurrence.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/payment_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BillRepository billRepository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final billsCollection = firestore.collection('bills').withConverter<Bill>(
          fromFirestore: Bill.fromFirestore,
          toFirestore: (b, _) => b.toFirestore(),
        );
    billRepository = BillRepository(billsCollection);
  });

  BillOccurrenceRepository occurrenceRepositoryFor(String billId) {
    final collection = firestore
        .collection('bills')
        .doc(billId)
        .collection('occurrences')
        .withConverter<BillOccurrence>(
          fromFirestore: BillOccurrence.fromFirestore,
          toFirestore: (o, _) => o.toFirestore(),
        );
    return BillOccurrenceRepository(
      collection,
      billRepository,
      firestore.collection('bills').doc(billId),
      firestore.collection('bills').doc(billId).collection('payments'),
    );
  }

  PaymentRepository paymentRepositoryFor(String billId, BillOccurrenceRepository occurrenceRepository) {
    final collection = firestore
        .collection('bills')
        .doc(billId)
        .collection('payments')
        .withConverter<PaymentRecord>(
          fromFirestore: PaymentRecord.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    return PaymentRepository(collection, occurrenceRepository);
  }

  Future<Bill> seedBill({
    double amount = 100,
    BillRecurrence recurrence = BillRecurrence.monthly,
    DateTime? dueDate,
  }) {
    return billRepository.createBill(
      name: 'Electricity',
      amount: amount,
      dueDate: dueDate ?? DateTime(2026, 3, 10),
      recurrence: recurrence,
    );
  }

  group('PaymentRepository.recordPayment', () {
    test('rejects a non-positive amount', () async {
      final bill = await seedBill();
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);

      await expectLater(
        payments.recordPayment(bill, occurrence, amount: 0, date: DateTime(2026, 3, 5)),
        throwsA(isA<AppException>()),
      );
    });

    test('applies the payment toward the occurrence\'s amountPaid and sets occurrenceId', () async {
      final bill = await seedBill(amount: 100);
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);

      final payment = await payments.recordPayment(bill, occurrence, amount: 40, date: DateTime(2026, 3, 5));

      expect(occurrence.amountPaid, 40);
      expect(payment.occurrenceId, occurrence.id);
    });

    test('a partial payment does not settle the occurrence', () async {
      final bill = await seedBill(amount: 100, dueDate: DateTime(2026, 3, 10));
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);

      await payments.recordPayment(bill, occurrence, amount: 40, date: DateTime(2026, 3, 5));

      expect(occurrence.dueDate, DateTime(2026, 3, 10));
      expect(occurrence.amountPaid, 40);
    });

    test('a full payment settles the occurrence without mutating its dueDate', () async {
      final bill = await seedBill(amount: 100, dueDate: DateTime(2026, 3, 10));
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);

      await payments.recordPayment(bill, occurrence, amount: 100, date: DateTime(2026, 3, 5));

      expect(occurrence.dueDate, DateTime(2026, 3, 10));
      expect(occurrence.amountPaid, 100);
    });

    test('multiple partial payments accumulate to a full payment', () async {
      final bill = await seedBill(amount: 100);
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);

      await payments.recordPayment(bill, occurrence, amount: 30, date: DateTime(2026, 3, 1));
      await payments.recordPayment(bill, occurrence, amount: 70, date: DateTime(2026, 3, 5));

      expect(occurrence.amountPaid, 100);
    });
  });

  group('PaymentRepository.softDeletePayment / restorePayment', () {
    test('softDeletePayment reverses the occurrence\'s amountPaid effect', () async {
      final bill = await seedBill(amount: 100);
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);
      final payment = await payments.recordPayment(bill, occurrence, amount: 40, date: DateTime(2026, 3, 5));

      await payments.softDeletePayment(occurrence, payment);

      expect(occurrence.amountPaid, 0);
      expect(payment.isDeleted, isTrue);
    });

    test('restorePayment re-applies the occurrence\'s amountPaid effect', () async {
      final bill = await seedBill(amount: 100);
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);
      final payment = await payments.recordPayment(bill, occurrence, amount: 40, date: DateTime(2026, 3, 5));
      await payments.softDeletePayment(occurrence, payment);

      await payments.restorePayment(occurrence, payment);

      expect(occurrence.amountPaid, 40);
      expect(payment.isDeleted, isFalse);
    });

    test('permanentlyDeletePayment does not change amountPaid again', () async {
      final bill = await seedBill(amount: 100);
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);
      final payment = await payments.recordPayment(bill, occurrence, amount: 40, date: DateTime(2026, 3, 5));
      await payments.softDeletePayment(occurrence, payment);

      await payments.permanentlyDeletePayment(payment);

      expect(occurrence.amountPaid, 0);
      expect(await payments.getByKey(payment.id), isNull);
    });
  });

  group('PaymentRepository.backfillOccurrenceId', () {
    test('sets occurrenceId without an audit entry', () async {
      final bill = await seedBill(amount: 100);
      final occurrences = occurrenceRepositoryFor(bill.id);
      final occurrence = await occurrences.ensureCurrentOccurrence(bill, const []);
      final payments = paymentRepositoryFor(bill.id, occurrences);
      final payment = await payments.recordPayment(bill, occurrence, amount: 40, date: DateTime(2026, 3, 5));

      await payments.backfillOccurrenceId(payment, 'other-occurrence');

      final updated = await payments.getByKey(payment.id);
      expect(updated!.occurrenceId, 'other-occurrence');
    });
  });
}
