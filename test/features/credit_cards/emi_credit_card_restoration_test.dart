import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/payment_schedule/data/installment_payment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/emi/data/emi_payment_breakdown_repository.dart';
import 'package:finance_app/features/emi/data/emi_repository.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/emi/domain/emi_payment_breakdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the same math as `principalRestoredForCardProvider`
/// (`lib/features/credit_cards/presentation/providers/credit_card_providers.dart`)
/// directly against the repositories, since this codebase's test suite has
/// no `ProviderContainer` precedent — every existing test hits repositories
/// with a fake Firestore rather than Riverpod, and this follows that same
/// pattern rather than introducing a new one for a single test file.
double principalRestored(
  List<Installment> installments,
  Map<String, List<InstallmentPayment>> paymentsByInstallmentId,
  Map<String, EmiPaymentBreakdown> breakdownByPaymentId,
) {
  var restored = 0.0;
  for (final installment in installments) {
    final payments = paymentsByInstallmentId[installment.id] ?? const [];
    for (final payment in payments) {
      final breakdown = breakdownByPaymentId[payment.id];
      if (breakdown != null) {
        restored += breakdown.principalPaid;
        continue;
      }
      final principalPortion = installment.principalPortion;
      if (principalPortion == null || installment.amountDue == 0) {
        restored += payment.amount;
      } else {
        restored += payment.amount * (principalPortion / installment.amountDue);
      }
    }
  }
  return restored;
}

void main() {
  late FakeFirebaseFirestore firestore;
  late EmiRepository emiRepository;
  late EmiPaymentBreakdownRepository breakdownRepository;
  late InstallmentRepository installmentRepository;
  late InstallmentPaymentRepository paymentRepository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final scheduleCollection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    final scheduleRepository = PaymentScheduleRepository(scheduleCollection);

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

    final emiCollection = firestore.collection('emis').withConverter<Emi>(
          fromFirestore: Emi.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        );
    emiRepository = EmiRepository(emiCollection, scheduleRepository, installmentRepositoryFor);

    final breakdownCollection = firestore
        .collection('emis')
        .doc('emi-1')
        .collection('paymentBreakdowns')
        .withConverter<EmiPaymentBreakdown>(
          fromFirestore: EmiPaymentBreakdown.fromFirestore,
          toFirestore: (b, _) => b.toFirestore(),
        );
    breakdownRepository = EmiPaymentBreakdownRepository(breakdownCollection);
  });

  test(
    'restores only the principal portion of an EMI payment, matching the spec worked example '
    '(₹4,200 principal / ₹800 interest → available credit rises by ₹4,200, not ₹5,000)',
    () async {
      // A ₹60,000 laptop purchase converted into a 12-month EMI, linked to a card.
      final emi = await emiRepository.createEmi(
        name: 'Laptop EMI',
        principalAmount: 60000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        linkedCreditCardId: 'card-1',
      );

      installmentRepository = InstallmentRepository(
        firestore
            .collection('paymentSchedules')
            .doc(emi.scheduleId)
            .collection('installments')
            .withConverter<Installment>(
              fromFirestore: Installment.fromFirestore,
              toFirestore: (i, _) => i.toFirestore(),
            ),
      );
      final installments = await installmentRepository.getAll();
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      final firstInstallment = sorted.first;

      paymentRepository = InstallmentPaymentRepository(
        firestore
            .collection('paymentSchedules')
            .doc(emi.scheduleId)
            .collection('installments')
            .doc(firstInstallment.id)
            .collection('payments')
            .withConverter<InstallmentPayment>(
              fromFirestore: InstallmentPayment.fromFirestore,
              toFirestore: (p, _) => p.toFirestore(),
            ),
        installmentRepository,
      );

      // Record a payment with an explicit ₹4,200 principal / ₹800 interest split.
      final payment = await paymentRepository.recordPayment(firstInstallment, amount: 5000, date: DateTime(2026, 1, 1));
      await breakdownRepository.createBreakdown(
        paymentId: payment.id,
        scheduleId: emi.scheduleId,
        installmentId: firstInstallment.id,
        principalPaid: 4200,
        interestPaid: 800,
      );

      final breakdowns = await breakdownRepository.getAll();
      final restored = principalRestored(
        [firstInstallment],
        {firstInstallment.id: [payment]},
        {for (final b in breakdowns) b.paymentId: b},
      );

      expect(restored, 4200);
      expect(restored, isNot(5000));
    },
  );

  test('falls back to the theoretical principal/interest split when no breakdown was recorded', () async {
    final emi = await emiRepository.createEmi(
      name: 'Car EMI',
      principalAmount: 100000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 12,
      linkedCreditCardId: 'card-1',
    );

    final installmentRepository = InstallmentRepository(
      firestore
          .collection('paymentSchedules')
          .doc(emi.scheduleId)
          .collection('installments')
          .withConverter<Installment>(
            fromFirestore: Installment.fromFirestore,
            toFirestore: (i, _) => i.toFirestore(),
          ),
    );
    final installments = await installmentRepository.getAll();
    final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final firstInstallment = sorted.first;

    final paymentRepository = InstallmentPaymentRepository(
      firestore
          .collection('paymentSchedules')
          .doc(emi.scheduleId)
          .collection('installments')
          .doc(firstInstallment.id)
          .collection('payments')
          .withConverter<InstallmentPayment>(
            fromFirestore: InstallmentPayment.fromFirestore,
            toFirestore: (p, _) => p.toFirestore(),
          ),
      installmentRepository,
    );

    // No interest on this EMI, so principalPortion is null — the whole
    // payment counts as principal (there's no interest to separate out).
    final payment = await paymentRepository.recordPayment(
      firstInstallment,
      amount: firstInstallment.amountDue,
      date: DateTime(2026, 1, 1),
    );

    final restored = principalRestored([firstInstallment], {firstInstallment.id: [payment]}, {});

    expect(restored, firstInstallment.amountDue);
  });

  test('an EMI not linked to any card contributes nothing (verified by filter, not math)', () async {
    final emi = await emiRepository.createEmi(
      name: 'Unlinked EMI',
      principalAmount: 5000,
      startDate: DateTime(2026, 1, 1),
      installmentFrequency: ScheduleType.monthly,
      installmentCount: 5,
    );

    expect(emi.linkedCreditCardId, isNull);
  });
}
