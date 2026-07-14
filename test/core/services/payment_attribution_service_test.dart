import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/models/payer_source.dart';
import 'package:finance_app/core/payment_schedule/data/installment_payment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/core/services/payment_attribution_service.dart';
import 'package:finance_app/features/bills/data/bill_repository.dart';
import 'package:finance_app/features/bills/data/payment_repository.dart';
import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/payment_record.dart';
import 'package:finance_app/features/emi/data/emi_repository.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/people/data/ledger_repository.dart';
import 'package:finance_app/features/people/data/person_repository.dart';
import 'package:finance_app/features/people/domain/ledger_entry.dart';
import 'package:finance_app/features/people/domain/person.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late PersonRepository personRepository;
  late PaymentAttributionService service;

  InstallmentRepository installmentRepositoryFor(String scheduleId) {
    final collection = firestore
        .collection('paymentSchedules')
        .doc(scheduleId)
        .collection('installments')
        .withConverter<Installment>(
          fromFirestore: Installment.fromFirestore,
          toFirestore: (i, _) => i.toFirestore(),
        );
    return InstallmentRepository(collection);
  }

  InstallmentPaymentRepository installmentPaymentRepositoryFor(String scheduleId, String installmentId) {
    final collection = firestore
        .collection('paymentSchedules')
        .doc(scheduleId)
        .collection('installments')
        .doc(installmentId)
        .collection('payments')
        .withConverter<InstallmentPayment>(
          fromFirestore: InstallmentPayment.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    return InstallmentPaymentRepository(collection, installmentRepositoryFor(scheduleId));
  }

  LedgerRepository ledgerRepositoryFor(String personId) {
    final collection = firestore
        .collection('people')
        .doc(personId)
        .collection('ledger')
        .withConverter<LedgerEntry>(
          fromFirestore: LedgerEntry.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        );
    return LedgerRepository(collection, personRepository);
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();

    final personCollection = firestore.collection('people').withConverter<Person>(
          fromFirestore: Person.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    personRepository = PersonRepository(personCollection);

    service = PaymentAttributionService(ledgerRepositoryFor: ledgerRepositoryFor);
  });

  group('PaymentAttributionService.apply — validation', () {
    test('rejects an empty item list', () async {
      await expectLater(
        service.apply(items: const [], payer: const PayerSource.self(), date: DateTime(2026, 1, 1)),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a non-positive amount', () async {
      var called = false;
      await expectLater(
        service.apply(
          items: [
            PaymentAttributionItem(
              obligationLabel: 'your Bike EMI',
              amount: 0,
              record: ({required amount, required date, required note}) async => called = true,
            ),
          ],
          payer: const PayerSource.self(),
          date: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AppException>()),
      );
      expect(called, false);
    });
  });

  group('PaymentAttributionService.apply — EMI installments (full/partial/advance/overdue)', () {
    late EmiRepository emiRepository;
    late PaymentScheduleRepository scheduleRepository;
    late Emi emi;

    setUp(() async {
      final scheduleCollection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
            fromFirestore: PaymentSchedule.fromFirestore,
            toFirestore: (s, _) => s.toFirestore(),
          );
      scheduleRepository = PaymentScheduleRepository(scheduleCollection);

      final emiCollection = firestore.collection('emis').withConverter<Emi>(
            fromFirestore: Emi.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );
      emiRepository = EmiRepository(emiCollection, scheduleRepository, installmentRepositoryFor);

      emi = await emiRepository.createEmi(
        name: 'Bike EMI',
        principalAmount: 1200,
        startDate: DateTime(2020, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
      );
    });

    Future<Installment> installmentAt(int sequenceNumber) async {
      final all = await installmentRepositoryFor(emi.scheduleId).getAll();
      return all.firstWhere((i) => i.sequenceNumber == sequenceNumber);
    }

    test('full payment: a friend pays one installment in full', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final installment = await installmentAt(1);

      final descriptions = await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Bike EMI',
            amount: installment.amountDue,
            record: ({required amount, required date, required note}) => installmentPaymentRepositoryFor(
              emi.scheduleId,
              installment.id,
            ).recordPayment(installment, amount: amount, date: date, note: note),
          ),
        ],
        payer: PayerSource.person(alice),
        date: DateTime(2026, 1, 1),
      );

      final refreshed = await installmentRepositoryFor(emi.scheduleId).getByKey(installment.id);
      expect(refreshed!.status, InstallmentStatus.paid);
      expect(refreshed.remainingAmount, 0);

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, -installment.amountDue, reason: 'you now owe Alice');

      expect(descriptions.single, 'Alice paid ₹100.00 towards your Bike EMI');
    });

    test('partial payment: a friend pays less than the full installment', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final installment = await installmentAt(1);
      final partial = installment.amountDue / 2;

      await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Bike EMI',
            amount: partial,
            record: ({required amount, required date, required note}) => installmentPaymentRepositoryFor(
              emi.scheduleId,
              installment.id,
            ).recordPayment(installment, amount: amount, date: date, note: note),
          ),
        ],
        payer: PayerSource.person(alice),
        date: DateTime(2026, 1, 1),
      );

      final refreshed = await installmentRepositoryFor(emi.scheduleId).getByKey(installment.id);
      expect(refreshed!.status, InstallmentStatus.partiallyPaid);
      expect(refreshed.remainingAmount, partial);

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, -partial);
    });

    test('advance payment: a friend pays an installment ahead of its scheduled turn', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final earlier = await installmentAt(1);
      final future = await installmentAt(6);
      expect(earlier.amountPaid, 0, reason: 'installment 1 has not been paid — this payment jumps ahead of it');

      await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Bike EMI',
            amount: future.amountDue,
            record: ({required amount, required date, required note}) => installmentPaymentRepositoryFor(
              emi.scheduleId,
              future.id,
            ).recordPayment(future, amount: amount, date: date, note: note),
          ),
        ],
        payer: PayerSource.person(alice),
        date: DateTime(2026, 1, 1),
      );

      final refreshed = await installmentRepositoryFor(emi.scheduleId).getByKey(future.id);
      expect(refreshed!.status, InstallmentStatus.paid);

      final refreshedEarlier = await installmentRepositoryFor(emi.scheduleId).getByKey(earlier.id);
      expect(refreshedEarlier!.amountPaid, 0, reason: 'paying ahead does not touch earlier installments');
    });

    test('overdue payment: a friend pays an installment already past its due date', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final overdueInstallment = await installmentAt(1);
      expect(overdueInstallment.status, InstallmentStatus.overdue, reason: 'startDate is in 2020, so installment 1 is overdue today');

      await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Bike EMI',
            amount: overdueInstallment.amountDue,
            record: ({required amount, required date, required note}) => installmentPaymentRepositoryFor(
              emi.scheduleId,
              overdueInstallment.id,
            ).recordPayment(overdueInstallment, amount: amount, date: date, note: note),
          ),
        ],
        payer: PayerSource.person(alice),
        date: DateTime.now(),
      );

      final refreshed = await installmentRepositoryFor(emi.scheduleId).getByKey(overdueInstallment.id);
      expect(refreshed!.status, InstallmentStatus.paid);
    });

    test('multiple installments paid together post ONE combined LedgerEntry', () async {
      final alice = await personRepository.createPerson(name: 'Alice', avatarColorValue: 0xFF5B5FEF, openingBalance: 0);
      final first = await installmentAt(1);
      final second = await installmentAt(2);

      final descriptions = await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Bike EMI (installment 1)',
            amount: first.amountDue,
            record: ({required amount, required date, required note}) => installmentPaymentRepositoryFor(
              emi.scheduleId,
              first.id,
            ).recordPayment(first, amount: amount, date: date, note: note),
          ),
          PaymentAttributionItem(
            obligationLabel: 'your Bike EMI (installment 2)',
            amount: second.amountDue,
            record: ({required amount, required date, required note}) => installmentPaymentRepositoryFor(
              emi.scheduleId,
              second.id,
            ).recordPayment(second, amount: amount, date: date, note: note),
          ),
        ],
        payer: PayerSource.person(alice),
        date: DateTime(2026, 1, 1),
      );

      expect(descriptions, hasLength(2));
      expect(descriptions[0], contains('installment 1'));
      expect(descriptions[1], contains('installment 2'));

      final refreshedFirst = await installmentRepositoryFor(emi.scheduleId).getByKey(first.id);
      final refreshedSecond = await installmentRepositoryFor(emi.scheduleId).getByKey(second.id);
      expect(refreshedFirst!.status, InstallmentStatus.paid);
      expect(refreshedSecond!.status, InstallmentStatus.paid);

      final refreshedAlice = await personRepository.getByKey(alice.id);
      expect(refreshedAlice!.currentBalance, -(first.amountDue + second.amountDue));

      final ledgerSnapshot = await firestore.collection('people').doc(alice.id).collection('ledger').get();
      expect(ledgerSnapshot.docs, hasLength(1), reason: 'one combined entry, not one per installment');
      expect((ledgerSnapshot.docs.single.data()['amount'] as num).toDouble(), first.amountDue + second.amountDue);
    });

    test('you paying yourself (PayerSource.self) posts no LedgerEntry', () async {
      final installment = await installmentAt(1);

      final descriptions = await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Bike EMI',
            amount: installment.amountDue,
            record: ({required amount, required date, required note}) => installmentPaymentRepositoryFor(
              emi.scheduleId,
              installment.id,
            ).recordPayment(installment, amount: amount, date: date, note: note),
          ),
        ],
        payer: const PayerSource.self(),
        date: DateTime(2026, 1, 1),
      );

      expect(descriptions.single, startsWith('You paid'));
      final peopleSnapshot = await firestore.collection('people').get();
      expect(peopleSnapshot.docs, isEmpty);
    });
  });

  group('PaymentAttributionService.apply — Bill payments', () {
    late BillRepository billRepository;
    late Bill bill;

    setUp(() async {
      final billCollection = firestore.collection('bills').withConverter<Bill>(
            fromFirestore: Bill.fromFirestore,
            toFirestore: (b, _) => b.toFirestore(),
          );
      billRepository = BillRepository(billCollection);

      bill = await billRepository.createBill(
        name: 'Electricity bill',
        amount: 2000,
        dueDate: DateTime(2026, 1, 10),
        recurrence: BillRecurrence.monthly,
      );
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

    test('a friend pays part of a bill (partial payment) and the person ledger updates', () async {
      final bob = await personRepository.createPerson(name: 'Bob', avatarColorValue: 0xFF00C2A8, openingBalance: 0);

      await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Electricity bill',
            amount: 800,
            record: ({required amount, required date, required note}) =>
                paymentRepositoryFor(bill.id).recordPayment(bill, amount: amount, date: date, note: note),
          ),
        ],
        payer: PayerSource.person(bob),
        date: DateTime(2026, 1, 5),
      );

      final refreshedBill = await billRepository.getByKey(bill.id);
      expect(refreshedBill!.amountPaid, 800);
      expect(refreshedBill.status.name, 'partiallyPaid');

      final refreshedBob = await personRepository.getByKey(bob.id);
      expect(refreshedBob!.currentBalance, -800);
    });

    test('a friend pays a one-time bill in full', () async {
      final bob = await personRepository.createPerson(name: 'Bob', avatarColorValue: 0xFF00C2A8, openingBalance: 0);
      final oneTimeBill = await billRepository.createBill(
        name: 'Laptop repair',
        amount: 2000,
        dueDate: DateTime(2026, 1, 10),
        recurrence: BillRecurrence.oneTime,
      );

      final descriptions = await service.apply(
        items: [
          PaymentAttributionItem(
            obligationLabel: 'your Laptop repair bill',
            amount: 2000,
            record: ({required amount, required date, required note}) =>
                paymentRepositoryFor(oneTimeBill.id).recordPayment(oneTimeBill, amount: amount, date: date, note: note),
          ),
        ],
        payer: PayerSource.person(bob),
        date: DateTime(2026, 1, 5),
      );

      final refreshedBill = await billRepository.getByKey(oneTimeBill.id);
      expect(refreshedBill!.amountPaid, 2000);
      expect(refreshedBill.status.name, 'paid');
      expect(descriptions.single, 'Bob paid ₹2,000.00 towards your Laptop repair bill');
    });
  });
}
