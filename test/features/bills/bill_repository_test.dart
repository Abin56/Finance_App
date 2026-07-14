import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/bills/data/bill_repository.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BillRepository repository;

  setUp(() {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('bills').withConverter<Bill>(
          fromFirestore: Bill.fromFirestore,
          toFirestore: (b, _) => b.toFirestore(),
        );
    repository = BillRepository(collection);
  });

  Future<Bill> seedBill({
    BillRecurrence recurrence = BillRecurrence.monthly,
    DateTime? dueDate,
    double amount = 100,
    int? customIntervalDays,
  }) {
    return repository.createBill(
      name: 'Electricity',
      amount: amount,
      dueDate: dueDate ?? DateTime(2026, 3, 10),
      recurrence: recurrence,
      customIntervalDays: customIntervalDays,
    );
  }

  group('BillRepository.createBill', () {
    test('rejects a non-positive amount', () async {
      await expectLater(
        repository.createBill(
          name: 'Rent',
          amount: 0,
          dueDate: DateTime(2026, 3, 1),
          recurrence: BillRecurrence.monthly,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects custom recurrence without a positive interval', () async {
      await expectLater(
        repository.createBill(
          name: 'Rent',
          amount: 100,
          dueDate: DateTime(2026, 3, 1),
          recurrence: BillRecurrence.custom,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('accepts custom recurrence with a positive interval', () async {
      final bill = await seedBill(recurrence: BillRecurrence.custom, customIntervalDays: 10);
      expect(bill.customIntervalDays, 10);
    });
  });

  group('BillRepository.editBill', () {
    test('rejects a non-positive amount', () async {
      final bill = await seedBill();
      await expectLater(repository.editBill(bill, amount: -5), throwsA(isA<AppException>()));
    });

    test('records an audit entry per changed field', () async {
      final bill = await seedBill();
      await repository.editBill(bill, name: 'Electricity Bill', amount: 150);
      expect(bill.editHistory.map((e) => e.field), containsAll(['name', 'amount']));
    });

    test('rejects switching to custom recurrence without an interval', () async {
      final bill = await seedBill();
      await expectLater(
        repository.editBill(bill, recurrence: BillRecurrence.custom),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('BillRepository.applyPayment', () {
    test('accumulates a partial payment', () async {
      final bill = await seedBill(amount: 100);
      await repository.applyPayment(bill, 40);
      expect(bill.amountPaid, 40);
    });

    test('clamps at the bill amount and rolls a recurring bill over on overshoot', () async {
      final bill = await seedBill(amount: 100, recurrence: BillRecurrence.monthly, dueDate: DateTime(2026, 3, 10));
      await repository.applyPayment(bill, 40);

      await repository.applyPayment(bill, 90);
      expect(bill.amountPaid, 0, reason: 'reached the full amount, so it rolled over to the next occurrence');
      expect(bill.dueDate, DateTime(2026, 4, 10));
    });

    test('clamps a one-time bill at the amount without rolling over', () async {
      final bill = await seedBill(amount: 100, recurrence: BillRecurrence.oneTime, dueDate: DateTime(2026, 3, 10));
      await repository.applyPayment(bill, 40);

      await repository.applyPayment(bill, 90);
      expect(bill.amountPaid, 100, reason: 'clamped at the bill amount, no rollover for one-time bills');
      expect(bill.dueDate, DateTime(2026, 3, 10));
    });

    test('is a no-op for a zero delta', () async {
      final bill = await seedBill();
      await repository.applyPayment(bill, 0);
      expect(bill.editHistory, isEmpty);
    });

    test('rolls a monthly bill forward once fully paid', () async {
      final bill = await seedBill(recurrence: BillRecurrence.monthly, dueDate: DateTime(2026, 3, 10), amount: 100);
      await repository.applyPayment(bill, 100);

      expect(bill.dueDate, DateTime(2026, 4, 10));
      expect(bill.amountPaid, 0, reason: 'reset for the new occurrence');
      expect(bill.isSkipped, isFalse);
    });

    test('does not roll a one-time bill forward once fully paid', () async {
      final bill = await seedBill(recurrence: BillRecurrence.oneTime, dueDate: DateTime(2026, 3, 10), amount: 100);
      await repository.applyPayment(bill, 100);

      expect(bill.dueDate, DateTime(2026, 3, 10));
      expect(bill.amountPaid, 100);
    });
  });

  group('BillRepository.markPaid', () {
    test('sets amountPaid to the full amount', () async {
      final bill = await seedBill(recurrence: BillRecurrence.oneTime, amount: 250);
      await repository.markPaid(bill);
      expect(bill.amountPaid, 250);
    });

    test('is a no-op when already fully paid', () async {
      final bill = await seedBill(recurrence: BillRecurrence.oneTime, amount: 250);
      await repository.markPaid(bill);
      final historyLengthAfterFirst = bill.editHistory.length;

      await repository.markPaid(bill);
      expect(bill.editHistory.length, historyLengthAfterFirst);
    });

    test('rolls a recurring bill forward', () async {
      final bill = await seedBill(recurrence: BillRecurrence.weekly, dueDate: DateTime(2026, 3, 10));
      await repository.markPaid(bill);
      expect(bill.dueDate, DateTime(2026, 3, 17));
      expect(bill.amountPaid, 0);
    });
  });

  group('BillRepository.skipOccurrence / unskip', () {
    test('skipOccurrence marks isSkipped and rolls a recurring bill forward', () async {
      final bill = await seedBill(recurrence: BillRecurrence.monthly, dueDate: DateTime(2026, 3, 10));
      await repository.skipOccurrence(bill);

      expect(bill.dueDate, DateTime(2026, 4, 10));
      expect(bill.isSkipped, isFalse, reason: 'reset for the new occurrence after rollover');
    });

    test('skipOccurrence on a one-time bill stays skipped, no rollover', () async {
      final bill = await seedBill(recurrence: BillRecurrence.oneTime, dueDate: DateTime(2026, 3, 10));
      await repository.skipOccurrence(bill);

      expect(bill.dueDate, DateTime(2026, 3, 10));
      expect(bill.isSkipped, isTrue);
    });

    test('unskip reverses isSkipped on a one-time bill', () async {
      final bill = await seedBill(recurrence: BillRecurrence.oneTime);
      await repository.skipOccurrence(bill);
      await repository.unskip(bill);
      expect(bill.isSkipped, isFalse);
    });

    test('unskip is a no-op when not skipped', () async {
      final bill = await seedBill();
      await repository.unskip(bill);
      expect(bill.editHistory, isEmpty);
    });
  });
}
