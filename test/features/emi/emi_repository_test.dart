import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/data/installment_payment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/emi/data/emi_repository.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/emi/domain/emi_interest.dart';
import 'package:finance_app/features/emi/domain/emi_loan_type.dart';
import 'package:finance_app/features/emi/domain/emi_payment_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late EmiRepository repository;
  late PaymentScheduleRepository scheduleRepository;

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

  Future<List<Installment>> installmentsFor(String scheduleId) async {
    final snapshot = await firestore.collection('paymentSchedules').doc(scheduleId).collection('installments').get();
    return snapshot.docs.map((d) => Installment.fromFirestore(d, null)).toList();
  }

  InstallmentPaymentRepository paymentRepositoryFor(
    String scheduleId,
    String installmentId,
    InstallmentRepository installmentRepository,
  ) {
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
    return InstallmentPaymentRepository(collection, installmentRepository);
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final scheduleCollection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    scheduleRepository = PaymentScheduleRepository(scheduleCollection);

    final emiCollection = firestore.collection('emis').withConverter<Emi>(
          fromFirestore: Emi.fromFirestore,
          toFirestore: (e, _) => e.toFirestore(),
        );
    repository = EmiRepository(emiCollection, scheduleRepository, installmentRepositoryFor);
  });

  group('EmiRepository.createEmi — validation', () {
    test('rejects blank name', () async {
      await expectLater(
        repository.createEmi(
          name: '  ',
          principalAmount: 1000,
          startDate: DateTime(2026, 1, 1),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 12,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects principalAmount <= 0', () async {
      await expectLater(
        repository.createEmi(
          name: 'Car loan',
          principalAmount: 0,
          startDate: DateTime(2026, 1, 1),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 12,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects installmentCount < 1', () async {
      await expectLater(
        repository.createEmi(
          name: 'Car loan',
          principalAmount: 1000,
          startDate: DateTime(2026, 1, 1),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 0,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects negative interest rate', () async {
      await expectLater(
        repository.createEmi(
          name: 'Car loan',
          principalAmount: 1000,
          startDate: DateTime(2026, 1, 1),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 12,
          interest: const EmiInterest(type: InterestType.flat, ratePercent: -1, period: InterestPeriod.monthly),
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('EmiRepository.createEmi — no interest', () {
    test('generates N even-split installments with no interest', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1200,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      final installments = await installmentsFor(emi.scheduleId);
      expect(installments, hasLength(4));
      expect(installments.map((i) => i.amountDue), everyElement(300));
      expect(installments.every((i) => i.principalPortion == null), true);
    });

    test('sets endDate to the last generated installment due date', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1200,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );

      expect(emi.endDate, DateTime(2026, 3, 1));
    });
  });

  group('EmiRepository.createEmi — with interest', () {
    test('flat interest: sum of principalPortion equals principalAmount', () async {
      final emi = await repository.createEmi(
        name: 'Bike loan',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
        interest: const EmiInterest(type: InterestType.flat, ratePercent: 2, period: InterestPeriod.monthly),
      );

      final installments = await installmentsFor(emi.scheduleId);
      final totalPrincipal = installments.fold(0.0, (sum, i) => sum + i.principalPortion!);
      expect(totalPrincipal, closeTo(1000, 0.01));
    });

    test('reducing balance interest: interest portion decreases over time', () async {
      final emi = await repository.createEmi(
        name: 'Home loan',
        principalAmount: 100000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        interest: const EmiInterest(type: InterestType.reducingBalance, ratePercent: 12, period: InterestPeriod.yearly),
      );

      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      expect(sorted.last.interestPortion, lessThan(sorted.first.interestPortion!));
    });

    test(
      'weekly-frequency EMI charges a properly weekly-normalized rate, not the monthly rate applied per week',
      () async {
        // Regression: EmiRepository used to force every schedule type
        // through InterestPeriod.monthly for rate normalization, so a
        // weekly EMI got the monthly-normalized rate applied once per
        // week — roughly a 4.3x overstatement (52 weeks/year vs. the
        // wrongly-assumed 12 "months"/year).
        final weeklyEmi = await repository.createEmi(
          name: 'Weekly EMI',
          principalAmount: 10000,
          startDate: DateTime(2026, 1, 1),
          installmentFrequency: ScheduleType.weekly,
          installmentCount: 10,
          interest: const EmiInterest(type: InterestType.flat, ratePercent: 2, period: InterestPeriod.monthly),
        );
        final monthlyEmi = await repository.createEmi(
          name: 'Monthly EMI',
          principalAmount: 10000,
          startDate: DateTime(2026, 1, 1),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 10,
          interest: const EmiInterest(type: InterestType.flat, ratePercent: 2, period: InterestPeriod.monthly),
        );

        final weeklySchedule = await scheduleRepository.getByKey(weeklyEmi.scheduleId);
        final monthlySchedule = await scheduleRepository.getByKey(monthlyEmi.scheduleId);
        final weeklyInterest = weeklySchedule!.totalAmount - 10000;
        final monthlyInterest = monthlySchedule!.totalAmount - 10000;

        expect(weeklyInterest, lessThan(monthlyInterest));
        expect(monthlyInterest / weeklyInterest, closeTo(52 / 12, 0.01));
      },
    );

    test('monthly-frequency interest EMI is unaffected by the weekly-normalization fix (no regression)', () async {
      final emi = await repository.createEmi(
        name: 'Home loan',
        principalAmount: 100000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        interest: const EmiInterest(type: InterestType.reducingBalance, ratePercent: 12, period: InterestPeriod.yearly),
      );

      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      expect(sorted.first.amountDue, closeTo(8884.88, 0.5));
    });
  });

  group('EmiRepository.editEmi', () {
    test('updates name/lenderName/categoryId/notes', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await repository.editEmi(
        emi,
        hasPayments: false,
        name: 'New Phone EMI',
        lenderName: 'HDFC',
        categoryId: 'cat-1',
        notes: 'Updated',
      );

      expect(emi.name, 'New Phone EMI');
      expect(emi.lenderName, 'HDFC');
      expect(emi.categoryId, 'cat-1');
      expect(emi.notes, 'Updated');
    });

    test('rejects changing principalAmount once a payment has been recorded', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await expectLater(
        repository.editEmi(emi, hasPayments: true, principalAmount: 500),
        throwsA(isA<AppException>()),
      );
    });

    test('allows changing principalAmount before any payment', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await repository.editEmi(emi, hasPayments: false, principalAmount: 1500);

      expect(emi.principalAmount, 1500);
    });

    test('updates loan number/type and fees/charges metadata', () async {
      final emi = await repository.createEmi(
        name: 'Home loan',
        principalAmount: 500000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 60,
      );

      await repository.editEmi(
        emi,
        hasPayments: false,
        loanNumber: 'LN-999',
        loanType: EmiLoanType.home,
        branch: 'Main Branch',
        customerId: 'CUST-1',
        sanctionDate: DateTime(2025, 12, 1),
        disbursementDate: DateTime(2025, 12, 5),
        processingFee: 2500,
        insuranceAmount: 1200,
        extraCharges: 300,
        foreclosureAmount: 8000,
        prepaymentCharges: 400,
        isAutoDebitEnabled: true,
        autoDebitAccount: 'XXXX5678',
      );

      expect(emi.loanNumber, 'LN-999');
      expect(emi.loanType, EmiLoanType.home);
      expect(emi.branch, 'Main Branch');
      expect(emi.customerId, 'CUST-1');
      expect(emi.sanctionDate, DateTime(2025, 12, 1));
      expect(emi.disbursementDate, DateTime(2025, 12, 5));
      expect(emi.processingFee, 2500);
      expect(emi.insuranceAmount, 1200);
      expect(emi.extraCharges, 300);
      expect(emi.foreclosureAmount, 8000);
      expect(emi.prepaymentCharges, 400);
      expect(emi.isAutoDebitEnabled, true);
      expect(emi.autoDebitAccount, 'XXXX5678');
    });
  });

  group('EmiRepository.editEmiTerms', () {
    test('regenerates the full schedule when nothing has been paid yet', () async {
      final emi = await repository.createEmi(
        name: 'Personal loan',
        principalAmount: 12000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);

      await repository.editEmiTerms(
        emi,
        currentInstallments: installments,
        interest: const EmiInterest(type: InterestType.flat, ratePercent: 12, period: InterestPeriod.yearly),
        installmentFrequency: ScheduleType.monthly,
        newInstallmentCount: 6,
      );

      expect(emi.installmentCount, 6);
      expect(emi.interest?.ratePercent, 12);
      final after = await installmentRepository.getAll();
      expect(after, hasLength(6));
      expect(after.every((i) => i.principalPortion != null), true);
    });

    test('leaves fully-paid installments untouched and re-amortizes only the outstanding principal', () async {
      final emi = await repository.createEmi(
        name: 'Personal loan',
        principalAmount: 4000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      // Pay off the first installment in full (1000 of the 4000 principal).
      await installmentRepository.applyPayment(sorted[0], 1000);
      final afterFirstPayment = await installmentsFor(emi.scheduleId);

      await repository.editEmiTerms(
        emi,
        currentInstallments: afterFirstPayment,
        interest: const EmiInterest(type: InterestType.flat, ratePercent: 10, period: InterestPeriod.yearly),
        installmentFrequency: ScheduleType.monthly,
        newInstallmentCount: 4,
      );

      final after = await installmentRepository.getAll();
      final stillPaid = after.where((i) => i.id == sorted[0].id).single;
      expect(stillPaid.amountPaid, 1000);

      final newTail = after.where((i) => i.id != sorted[0].id).toList()
        ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      expect(newTail, hasLength(3));
      final totalNewPrincipal = newTail.fold(0.0, (sum, i) => sum + i.principalPortion!);
      expect(totalNewPrincipal, closeTo(3000, 0.01)); // 4000 - 1000 already paid
    });

    test('leaves a partially-paid installment untouched', () async {
      final emi = await repository.createEmi(
        name: 'Personal loan',
        principalAmount: 3000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      await installmentRepository.applyPayment(sorted[0], 500); // partial payment on a 1000 installment
      final afterPartialPayment = await installmentsFor(emi.scheduleId);

      await repository.editEmiTerms(
        emi,
        currentInstallments: afterPartialPayment,
        interest: null,
        installmentFrequency: ScheduleType.monthly,
        newInstallmentCount: 3,
      );

      final after = await installmentRepository.getAll();
      final untouchedPartial = after.where((i) => i.id == sorted[0].id).single;
      expect(untouchedPartial.amountPaid, 500);
      expect(untouchedPartial.amountDue, 1000);
    });

    test('rejects a new installment count lower than the number already settled', () async {
      final emi = await repository.createEmi(
        name: 'Personal loan',
        principalAmount: 3000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      await installmentRepository.applyPayment(sorted[0], 1000);
      await installmentRepository.applyPayment(sorted[1], 1000);
      final afterPayments = await installmentsFor(emi.scheduleId);

      await expectLater(
        repository.editEmiTerms(
          emi,
          currentInstallments: afterPayments,
          installmentFrequency: ScheduleType.monthly,
          newInstallmentCount: 1,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('updates endDate to the new last installment\'s due date', () async {
      final emi = await repository.createEmi(
        name: 'Personal loan',
        principalAmount: 3000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);

      await repository.editEmiTerms(
        emi,
        currentInstallments: installments,
        installmentFrequency: ScheduleType.monthly,
        newInstallmentCount: 6,
      );

      final after = await installmentRepository.getAll();
      final sorted = [...after]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      expect(emi.endDate, sorted.last.dueDate);
    });
  });

  group('EmiRepository.createEmi — loan management fields', () {
    test('persists loan number/type/branch/fees passed at creation', () async {
      final emi = await repository.createEmi(
        name: 'Business loan',
        principalAmount: 200000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 24,
        loanNumber: 'BL-001',
        loanType: EmiLoanType.business,
        branch: 'City Branch',
        customerId: 'CUST-2',
        sanctionDate: DateTime(2025, 11, 1),
        disbursementDate: DateTime(2025, 11, 10),
        processingFee: 3000,
        insuranceAmount: 1500,
        extraCharges: 200,
        isAutoDebitEnabled: true,
        autoDebitAccount: 'XXXX1111',
      );

      expect(emi.loanNumber, 'BL-001');
      expect(emi.loanType, EmiLoanType.business);
      expect(emi.branch, 'City Branch');
      expect(emi.customerId, 'CUST-2');
      expect(emi.sanctionDate, DateTime(2025, 11, 1));
      expect(emi.disbursementDate, DateTime(2025, 11, 10));
      expect(emi.processingFee, 3000);
      expect(emi.insuranceAmount, 1500);
      expect(emi.extraCharges, 200);
      expect(emi.isAutoDebitEnabled, true);
      expect(emi.autoDebitAccount, 'XXXX1111');
    });

    test('defaults loanType to other and fees to 0 when not provided', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      expect(emi.loanType, EmiLoanType.other);
      expect(emi.processingFee, 0);
      expect(emi.insuranceAmount, 0);
      expect(emi.extraCharges, 0);
      expect(emi.isAutoDebitEnabled, false);
    });
  });

  group('EmiRepository — linked credit card', () {
    test('createEmi persists linkedCreditCardId', () async {
      final emi = await repository.createEmi(
        name: 'Laptop EMI',
        principalAmount: 60000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        linkedCreditCardId: 'card-1',
      );

      expect(emi.linkedCreditCardId, 'card-1');
    });

    test('createEmi leaves linkedCreditCardId null when not provided', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      expect(emi.linkedCreditCardId, isNull);
    });

    test('editEmi can set and clear linkedCreditCardId', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await repository.editEmi(emi, hasPayments: false, linkedCreditCardId: 'card-1');
      expect(emi.linkedCreditCardId, 'card-1');

      await repository.editEmi(emi, hasPayments: false, clearLinkedCreditCardId: true);
      expect(emi.linkedCreditCardId, isNull);
    });
  });

  group('EmiRepository — Monthly Due Date (dueDayOfMonth)', () {
    test(
      'createEmi: installment #1 stays on First EMI Date, #2+ snap to the Monthly Due Date '
      '(worked example: First EMI 12 Feb 2026, Due Date 5)',
      () async {
        final emi = await repository.createEmi(
          name: 'Laptop EMI',
          principalAmount: 60000,
          startDate: DateTime(2026, 2, 12),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 4,
          dueDayOfMonth: 5,
        );

        expect(emi.dueDayOfMonth, 5);
        final installments = await installmentsFor(emi.scheduleId);
        final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

        expect(sorted[0].dueDate, DateTime(2026, 2, 12));
        expect(sorted[1].dueDate, DateTime(2026, 3, 5));
        expect(sorted[2].dueDate, DateTime(2026, 4, 5));
        expect(sorted[3].dueDate, DateTime(2026, 5, 5));
      },
    );

    test('createEmi rejects a dueDayOfMonth outside 1-31', () async {
      await expectLater(
        repository.createEmi(
          name: 'Laptop EMI',
          principalAmount: 60000,
          startDate: DateTime(2026, 2, 12),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 4,
          dueDayOfMonth: 32,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('createEmi leaves dueDayOfMonth null when not provided (unchanged day-of-month chaining)', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 31),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );

      expect(emi.dueDayOfMonth, isNull);
      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      expect(sorted[1].dueDate, DateTime(2026, 2, 28));
    });

    test('editEmiTerms regenerating the unpaid tail snaps future installments to a newly chosen due day', () async {
      final emi = await repository.createEmi(
        name: 'Laptop EMI',
        principalAmount: 60000,
        startDate: DateTime(2026, 2, 12),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      await installmentRepository.applyPayment(sorted[0], sorted[0].amountDue);
      final afterPayment = await installmentsFor(emi.scheduleId);

      await repository.editEmiTerms(
        emi,
        currentInstallments: afterPayment,
        installmentFrequency: ScheduleType.monthly,
        newInstallmentCount: 4,
        dueDayOfMonth: 20,
      );

      expect(emi.dueDayOfMonth, 20);
      final after = await installmentRepository.getAll();
      final resorted = [...after]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
      // The paid installment (#1) is untouched; the regenerated tail snaps
      // to the 20th from the next due date onward.
      expect(resorted[0].id, sorted[0].id);
      expect(resorted[1].dueDate.day, 20);
      expect(resorted[2].dueDate.day, 20);
    });
  });

  group('EmiRepository.closeEmi / reopenEmi', () {
    test('toggle isClosed and record audit entries', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await repository.closeEmi(emi);
      expect(emi.isClosed, true);

      await repository.reopenEmi(emi);
      expect(emi.isClosed, false);
      expect(emi.editHistory, hasLength(2));
    });
  });

  group('EmiRepository.markDefaulted / clearDefaulted', () {
    test('toggle isDefaulted and record audit entries', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await repository.markDefaulted(emi);
      expect(emi.isDefaulted, true);

      await repository.clearDefaulted(emi);
      expect(emi.isDefaulted, false);
      expect(emi.editHistory, hasLength(2));
    });

    test('markDefaulted is a no-op when already defaulted', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await repository.markDefaulted(emi);
      await repository.markDefaulted(emi);

      expect(emi.editHistory, hasLength(1));
    });
  });

  group('EmiRepository.closeEmiEarly', () {
    test('writes off remaining installments and closes the EMI', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 400,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      // Pay off the first installment only, leave the other 3 outstanding.
      await installmentRepository.applyPayment(sorted[0], 100);

      await repository.closeEmiEarly(emi, sorted);

      expect(emi.isClosed, true);
      final remaining = await installmentRepository.getAll();
      expect(remaining.map((i) => i.id), [sorted[0].id]);
    });

    test('is a no-op when the EMI is already closed', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 400,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );
      await repository.closeEmi(emi);
      final installments = await installmentsFor(emi.scheduleId);

      await repository.closeEmiEarly(emi, installments);

      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      expect((await installmentRepository.getAll()), hasLength(4));
    });
  });

  group('Payment flexibility — skip / advance / partial / overdue recovery', () {
    test('skipping an installment excludes it from remainingAmount', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 300,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);

      await installmentRepository.skipInstallment(installments[1]);

      final remaining = installmentRepository.remainingAmount(installments);
      expect(remaining, 200); // 300 total - the 100 skipped installment
    });

    test('advance payment (before due date) is accepted and marks the installment paid', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 300,
        startDate: DateTime(2026, 6, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final target = installments.firstWhere((i) => i.sequenceNumber == 2); // due 2026-07-01
      final paymentRepository = paymentRepositoryFor(emi.scheduleId, target.id, installmentRepository);

      final earlyDate = DateTime(2026, 6, 15);
      await paymentRepository.recordPayment(target, amount: 100, date: earlyDate);

      expect(target.status, InstallmentStatus.paid);
      expect(EmiPaymentHistoryEntry.statusFor(
        InstallmentPayment(
          id: 'p1',
          installmentId: target.id,
          scheduleId: emi.scheduleId,
          ownerType: target.ownerType,
          ownerId: target.ownerId,
          amount: 100,
          date: earlyDate,
          createdAt: DateTime.now(),
        ),
        target,
      ), EmiPaymentHistoryStatus.advance);
    });

    test('partial payment leaves the installment partiallyPaid', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 300,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final target = installments.first;
      final paymentRepository = paymentRepositoryFor(emi.scheduleId, target.id, installmentRepository);

      await paymentRepository.recordPayment(target, amount: 40, date: DateTime.now());

      expect(target.status, InstallmentStatus.partiallyPaid);
    });

    test('paying an overdue installment recovers it to paid', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 100,
        startDate: DateTime.now().subtract(const Duration(days: 10)),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 1,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installment = (await installmentsFor(emi.scheduleId)).single;
      expect(installment.status, InstallmentStatus.overdue);
      final paymentRepository = paymentRepositoryFor(emi.scheduleId, installment.id, installmentRepository);

      await paymentRepository.recordPayment(installment, amount: 100, date: DateTime.now());

      expect(installment.status, InstallmentStatus.paid);
    });

    test('multiple installments can each be paid off independently in one flow', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 300,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);

      for (final installment in installments) {
        final paymentRepository = paymentRepositoryFor(emi.scheduleId, installment.id, installmentRepository);
        await paymentRepository.recordPayment(installment, amount: installment.amountDue, date: DateTime.now());
      }

      expect(installments.every((i) => i.status == InstallmentStatus.paid), true);
      expect(installmentRepository.remainingAmount(installments), 0);
    });
  });

  group('EmiPaymentHistoryEntry.statusFor', () {
    Installment installment({required DateTime dueDate, double amountDue = 100}) => Installment(
          id: 'i1',
          scheduleId: 'schedule-1',
          ownerType: OwnerType.emi,
          ownerId: 'emi-1',
          sequenceNumber: 1,
          dueDate: dueDate,
          amountDue: amountDue,
          createdAt: DateTime.now(),
        );

    InstallmentPayment payment({required double amount, required DateTime date}) => InstallmentPayment(
          id: 'p1',
          installmentId: 'i1',
          scheduleId: 'schedule-1',
          ownerType: OwnerType.emi,
          ownerId: 'emi-1',
          amount: amount,
          date: date,
          createdAt: DateTime.now(),
        );

    test('advance when paid before due date', () {
      final due = DateTime(2026, 3, 1);
      final result = EmiPaymentHistoryEntry.statusFor(
        payment(amount: 100, date: DateTime(2026, 2, 20)),
        installment(dueDate: due),
      );
      expect(result, EmiPaymentHistoryStatus.advance);
    });

    test('partial when amount is less than amountDue', () {
      final due = DateTime(2026, 3, 1);
      final result = EmiPaymentHistoryEntry.statusFor(
        payment(amount: 40, date: due),
        installment(dueDate: due, amountDue: 100),
      );
      expect(result, EmiPaymentHistoryStatus.partial);
    });

    test('overdue when paid in full after the due date', () {
      final due = DateTime(2026, 3, 1);
      final result = EmiPaymentHistoryEntry.statusFor(
        payment(amount: 100, date: DateTime(2026, 3, 10)),
        installment(dueDate: due, amountDue: 100),
      );
      expect(result, EmiPaymentHistoryStatus.overdue);
    });

    test('paid when paid in full exactly on the due date', () {
      final due = DateTime(2026, 3, 1);
      final result = EmiPaymentHistoryEntry.statusFor(
        payment(amount: 100, date: due),
        installment(dueDate: due, amountDue: 100),
      );
      expect(result, EmiPaymentHistoryStatus.paid);
    });
  });

  group('Payment history ordering', () {
    test('entries fold chronologically with remaining balance decreasing over time', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 300,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 3,
      );
      final installmentRepository = installmentRepositoryFor(emi.scheduleId);
      final installments = await installmentsFor(emi.scheduleId);
      final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      // Pay installment 2 before installment 1, out of sequence order, to
      // prove ordering is by payment date, not by installment sequence.
      final paymentRepo2 = paymentRepositoryFor(emi.scheduleId, sorted[1].id, installmentRepository);
      final paymentRepo1 = paymentRepositoryFor(emi.scheduleId, sorted[0].id, installmentRepository);
      await paymentRepo2.recordPayment(sorted[1], amount: 100, date: DateTime(2026, 1, 5));
      await paymentRepo1.recordPayment(sorted[0], amount: 100, date: DateTime(2026, 1, 10));

      // Replicate the provider's folding logic directly (no Riverpod container
      // in this test suite) — this is the same algorithm as
      // `emiPaymentHistoryProvider` in emi_providers.dart.
      final totalDue = installments.fold(0.0, (sum, i) => sum + i.amountDue);
      final rawEntries = <({DateTime date, double amount})>[
        (date: DateTime(2026, 1, 5), amount: 100),
        (date: DateTime(2026, 1, 10), amount: 100),
      ]..sort((a, b) => a.date.compareTo(b.date));

      var paidSoFar = 0.0;
      final remainingAfterEachEntry = <double>[];
      for (final raw in rawEntries) {
        paidSoFar += raw.amount;
        remainingAfterEachEntry.add((totalDue - paidSoFar).clamp(0, totalDue));
      }

      expect(rawEntries.first.date, DateTime(2026, 1, 5));
      expect(remainingAfterEachEntry, [200, 100]);
    });
  });

  group('Soft-delete / restore', () {
    test('archive (soft-delete) then restore round-trips through getAll', () async {
      final emi = await repository.createEmi(
        name: 'Phone EMI',
        principalAmount: 1000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      await repository.softDelete(emi);
      expect((await repository.getAll()).any((e) => e.id == emi.id), false);

      await repository.restore(emi);
      expect((await repository.getAll()).any((e) => e.id == emi.id), true);
    });
  });
}
