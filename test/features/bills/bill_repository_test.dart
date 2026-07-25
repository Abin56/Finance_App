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

    test('sets nextDueDate from the given dueDate', () async {
      final bill = await seedBill(dueDate: DateTime(2026, 3, 10));
      expect(bill.nextDueDate, DateTime(2026, 3, 10));
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

    test('editing nextDueDate never touches an occurrence — it is a template-only field', () async {
      final bill = await seedBill(dueDate: DateTime(2026, 3, 10));
      await repository.editBill(bill, nextDueDate: DateTime(2026, 3, 20));
      expect(bill.nextDueDate, DateTime(2026, 3, 20));
    });
  });

  group('BillRepository.advanceNextDueDate', () {
    test('advances nextDueDate and records an audit entry', () async {
      final bill = await seedBill(dueDate: DateTime(2026, 3, 10));
      await repository.advanceNextDueDate(bill, DateTime(2026, 4, 10));

      expect(bill.nextDueDate, DateTime(2026, 4, 10));
      expect(bill.editHistory.map((e) => e.field), contains('nextDueDate'));
    });
  });
}
