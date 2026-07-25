import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/payment_schedule/data/installment_payment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late InstallmentRepository installmentRepository;
  late InstallmentPaymentRepository paymentRepository;
  late Installment installment;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    final scheduleCollection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    final scheduleRepository = PaymentScheduleRepository(scheduleCollection);

    final installmentCollection = firestore.collection('installments').withConverter<Installment>(
          fromFirestore: Installment.fromFirestore,
          toFirestore: (i, _) => i.toFirestore(),
        );
    installmentRepository = InstallmentRepository(installmentCollection);

    final paymentCollection = firestore.collection('payments').withConverter<InstallmentPayment>(
          fromFirestore: InstallmentPayment.fromFirestore,
          toFirestore: (p, _) => p.toFirestore(),
        );
    paymentRepository = InstallmentPaymentRepository(paymentCollection, installmentRepository);

    final schedule = await scheduleRepository.createSchedule(
      ownerType: OwnerType.loan,
      ownerId: 'loan-1',
      totalAmount: 1000,
      scheduleType: ScheduleType.oneTime,
      firstDueDate: DateTime.now().add(const Duration(days: 30)),
      installmentCount: 1,
    );
    installment = (await installmentRepository.generateInstallments(schedule)).single;
  });

  group('InstallmentPaymentRepository.recordPayment', () {
    test('rejects amount <= 0', () async {
      await expectLater(
        paymentRepository.recordPayment(installment, amount: 0, date: DateTime.now()),
        throwsA(isA<AppException>()),
      );
    });

    test('creates the payment and applies it to the installment', () async {
      await paymentRepository.recordPayment(installment, amount: 400, date: DateTime.now());

      expect(installment.amountPaid, 400);
    });

    test('partial payment leaves status == partiallyPaid', () async {
      await paymentRepository.recordPayment(installment, amount: 300, date: DateTime.now());

      expect(installment.status, InstallmentStatus.partiallyPaid);
    });

    test('advance/early payment (before due date) is accepted with no special validation', () async {
      final earlyDate = installment.dueDate.subtract(const Duration(days: 20));

      await paymentRepository.recordPayment(installment, amount: 1000, date: earlyDate);

      expect(installment.amountPaid, 1000);
      expect(installment.status, InstallmentStatus.paid);
    });

    test('overpayment is clamped by applyPayment', () async {
      await paymentRepository.recordPayment(installment, amount: 5000, date: DateTime.now());

      expect(installment.amountPaid, 1000);
    });

    test('records settlementMethod/billingCycleLabel and computes remainingBalanceAfterPayment', () async {
      final payment = await paymentRepository.recordPayment(
        installment,
        amount: 400,
        date: DateTime.now(),
        settlementMethod: 'UPI',
        billingCycleLabel: 'Jul 2026',
      );

      expect(payment.settlementMethod, 'UPI');
      expect(payment.billingCycleLabel, 'Jul 2026');
      expect(payment.remainingBalanceAfterPayment, 600);
    });

    test('settlementMethod/billingCycleLabel default to null when not supplied', () async {
      final payment = await paymentRepository.recordPayment(installment, amount: 400, date: DateTime.now());

      expect(payment.settlementMethod, isNull);
      expect(payment.billingCycleLabel, isNull);
      expect(payment.remainingBalanceAfterPayment, 600);
    });

    // Case 2: multiple partial payments across advancing dates each get
    // their own remainingBalanceAfterPayment snapshot and both are kept as
    // distinct, independently-readable records.
    test('multiple partial payments each record their own remainingBalanceAfterPayment', () async {
      final first = await paymentRepository.recordPayment(
        installment,
        amount: 400,
        date: DateTime(2026, 1, 20),
        billingCycleLabel: 'Jan 2026',
      );
      final second = await paymentRepository.recordPayment(
        installment,
        amount: 200,
        date: DateTime(2026, 2, 20),
        billingCycleLabel: 'Feb 2026',
      );

      expect(first.remainingBalanceAfterPayment, 600);
      expect(second.remainingBalanceAfterPayment, 400);
      expect(first.billingCycleLabel, 'Jan 2026');
      expect(second.billingCycleLabel, 'Feb 2026');
      expect(installment.amountPaid, 600);
    });
  });

  group('InstallmentPaymentRepository.softDeletePayment / restorePayment', () {
    test('softDeletePayment reverses amountPaid and moves the payment to trash', () async {
      final payment = await paymentRepository.recordPayment(installment, amount: 400, date: DateTime.now());
      expect(installment.status, InstallmentStatus.partiallyPaid);

      await paymentRepository.softDeletePayment(installment, payment);

      expect(installment.amountPaid, 0);
      expect(installment.status, InstallmentStatus.upcoming);
      expect(payment.isDeleted, true);
    });

    test('restorePayment re-applies the effect and restores from trash', () async {
      final payment = await paymentRepository.recordPayment(installment, amount: 400, date: DateTime.now());
      await paymentRepository.softDeletePayment(installment, payment);

      await paymentRepository.restorePayment(installment, payment);

      expect(installment.amountPaid, 400);
      expect(payment.isDeleted, false);
    });
  });

  group('InstallmentPaymentRepository.permanentlyDeletePayment', () {
    test('does not further change amountPaid', () async {
      final payment = await paymentRepository.recordPayment(installment, amount: 400, date: DateTime.now());
      await paymentRepository.softDeletePayment(installment, payment);

      await paymentRepository.permanentlyDeletePayment(payment);

      expect(installment.amountPaid, 0);
    });
  });
}
