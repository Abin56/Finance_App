import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/bills/data/bill_repository.dart';
import 'package:finance_app/features/bills/data/payment_repository.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
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

  PaymentRepository paymentRepositoryFor(String billId) {
    final collection = firestore
        .collection('bills')
        .doc(billId)
        .collection('payments')
        .withConverter<PaymentRecord>(
          fromFirestore: PaymentRecord.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    return PaymentRepository(collection, billRepository);
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
      final payments = paymentRepositoryFor(bill.id);

      await expectLater(
        payments.recordPayment(bill, amount: 0, date: DateTime(2026, 3, 5)),
        throwsA(isA<AppException>()),
      );
    });

    test('applies the payment toward the bill amountPaid', () async {
      final bill = await seedBill(amount: 100);
      final payments = paymentRepositoryFor(bill.id);

      await payments.recordPayment(bill, amount: 40, date: DateTime(2026, 3, 5));

      final updated = await billRepository.getByKey(bill.id);
      expect(updated!.amountPaid, 40);
    });

    test('a partial payment does not roll the bill over', () async {
      final bill = await seedBill(amount: 100, dueDate: DateTime(2026, 3, 10));
      final payments = paymentRepositoryFor(bill.id);

      await payments.recordPayment(bill, amount: 40, date: DateTime(2026, 3, 5));

      final updated = await billRepository.getByKey(bill.id);
      expect(updated!.dueDate, DateTime(2026, 3, 10));
    });

    test('a full payment rolls a recurring bill over', () async {
      final bill = await seedBill(amount: 100, dueDate: DateTime(2026, 3, 10));
      final payments = paymentRepositoryFor(bill.id);

      await payments.recordPayment(bill, amount: 100, date: DateTime(2026, 3, 5));

      final updated = await billRepository.getByKey(bill.id);
      expect(updated!.dueDate, DateTime(2026, 4, 10));
      expect(updated.amountPaid, 0);
    });

    test('multiple partial payments accumulate to a full payment', () async {
      final bill = await seedBill(amount: 100);
      final payments = paymentRepositoryFor(bill.id);

      await payments.recordPayment(bill, amount: 30, date: DateTime(2026, 3, 1));
      await payments.recordPayment(bill, amount: 70, date: DateTime(2026, 3, 5));

      final updated = await billRepository.getByKey(bill.id);
      expect(updated!.amountPaid, 0, reason: 'rolled over after reaching the full amount');
    });
  });

  group('PaymentRepository.softDeletePayment / restorePayment', () {
    test('softDeletePayment reverses the amountPaid effect', () async {
      final bill = await seedBill(amount: 100);
      final payments = paymentRepositoryFor(bill.id);
      final payment = await payments.recordPayment(bill, amount: 40, date: DateTime(2026, 3, 5));

      await payments.softDeletePayment(bill, payment);

      final updated = await billRepository.getByKey(bill.id);
      expect(updated!.amountPaid, 0);
      expect(payment.isDeleted, isTrue);
    });

    test('restorePayment re-applies the amountPaid effect', () async {
      final bill = await seedBill(amount: 100);
      final payments = paymentRepositoryFor(bill.id);
      final payment = await payments.recordPayment(bill, amount: 40, date: DateTime(2026, 3, 5));
      await payments.softDeletePayment(bill, payment);

      await payments.restorePayment(bill, payment);

      final updated = await billRepository.getByKey(bill.id);
      expect(updated!.amountPaid, 40);
      expect(payment.isDeleted, isFalse);
    });

    test('permanentlyDeletePayment does not change amountPaid again', () async {
      final bill = await seedBill(amount: 100);
      final payments = paymentRepositoryFor(bill.id);
      final payment = await payments.recordPayment(bill, amount: 40, date: DateTime(2026, 3, 5));
      await payments.softDeletePayment(bill, payment);

      await payments.permanentlyDeletePayment(payment);

      final updated = await billRepository.getByKey(bill.id);
      expect(updated!.amountPaid, 0);
      expect(await payments.getByKey(payment.id), isNull);
    });
  });
}
