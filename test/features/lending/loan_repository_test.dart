import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/data/installment_repository.dart';
import 'package:finance_app/core/payment_schedule/data/payment_schedule_repository.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/payment_schedule.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/lending/data/loan_repository.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_interest.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late LoanRepository repository;
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

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final scheduleCollection = firestore.collection('paymentSchedules').withConverter<PaymentSchedule>(
          fromFirestore: PaymentSchedule.fromFirestore,
          toFirestore: (s, _) => s.toFirestore(),
        );
    scheduleRepository = PaymentScheduleRepository(scheduleCollection);

    final loanCollection = firestore.collection('loans').withConverter<Loan>(
          fromFirestore: Loan.fromFirestore,
          toFirestore: (l, _) => l.toFirestore(),
        );
    repository = LoanRepository(loanCollection, scheduleRepository, installmentRepositoryFor);
  });

  group('LoanRepository.createLoan — validation', () {
    test('rejects loanAmount <= 0', () async {
      await expectLater(
        repository.createLoan(
          personId: 'p1',
          loanAmount: 0,
          loanDate: DateTime(2026, 1, 1),
          repaymentType: LoanRepaymentType.oneTime,
          dueDate: DateTime(2026, 2, 1),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('oneTime without dueDate throws', () async {
      await expectLater(
        repository.createLoan(
          personId: 'p1',
          loanAmount: 100,
          loanDate: DateTime(2026, 1, 1),
          repaymentType: LoanRepaymentType.oneTime,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('installment without installmentFrequency/installmentCount throws', () async {
      await expectLater(
        repository.createLoan(
          personId: 'p1',
          loanAmount: 100,
          loanDate: DateTime(2026, 1, 1),
          repaymentType: LoanRepaymentType.installment,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('negative interest rate throws', () async {
      await expectLater(
        repository.createLoan(
          personId: 'p1',
          loanAmount: 100,
          loanDate: DateTime(2026, 1, 1),
          repaymentType: LoanRepaymentType.oneTime,
          dueDate: DateTime(2026, 2, 1),
          interest: const LoanInterest(type: InterestType.flat, ratePercent: -1, period: InterestPeriod.monthly),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('installmentCount < 1 throws', () async {
      await expectLater(
        repository.createLoan(
          personId: 'p1',
          loanAmount: 100,
          loanDate: DateTime(2026, 1, 1),
          repaymentType: LoanRepaymentType.installment,
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 0,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('LoanRepository.createLoan — no interest', () {
    test('oneTime loan creates a schedule with a single installment, no principal/interest split', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
      );

      final schedule = await scheduleRepository.getByKey(loan.scheduleId);
      expect(schedule!.totalAmount, 1000);

      final installments = await installmentsFor(loan.scheduleId);
      expect(installments, hasLength(1));
      expect(installments.single.amountDue, 1000);
      expect(installments.single.principalPortion, isNull);
      expect(installments.single.interestPortion, isNull);
    });

    test('installment loan creates N even-split installments with no interest', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1200,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
      );

      final installments = await installmentsFor(loan.scheduleId);
      expect(installments, hasLength(4));
      expect(installments.map((i) => i.amountDue), everyElement(300));
      expect(installments.every((i) => i.principalPortion == null), true);
    });
  });

  group('LoanRepository.createLoan — with interest', () {
    test('flat interest: schedule.totalAmount == loanAmount + totalInterest', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 4,
        interest: const LoanInterest(type: InterestType.flat, ratePercent: 2, period: InterestPeriod.monthly),
      );

      final schedule = await scheduleRepository.getByKey(loan.scheduleId);
      final installments = await installmentsFor(loan.scheduleId);
      final totalPrincipal = installments.fold(0.0, (sum, i) => sum + i.principalPortion!);
      final totalInterest = installments.fold(0.0, (sum, i) => sum + i.interestPortion!);

      expect(schedule!.totalAmount, closeTo(1000 + totalInterest, 0.01));
      expect(totalPrincipal, closeTo(1000, 0.01));
    });

    test('reducing balance interest: per-installment principal/interest sums correctly', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 100000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 12,
        interest: const LoanInterest(type: InterestType.reducingBalance, ratePercent: 12, period: InterestPeriod.yearly),
      );

      final installments = await installmentsFor(loan.scheduleId);
      final totalPrincipal = installments.fold(0.0, (sum, i) => sum + i.principalPortion!);
      expect(totalPrincipal, closeTo(100000, 0.01));
      expect(installments.last.interestPortion, lessThan(installments.first.interestPortion!));
    });

    test('one-time loan with interest still creates a single installment', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        interest: const LoanInterest(type: InterestType.flat, ratePercent: 5, period: InterestPeriod.monthly),
      );

      final installments = await installmentsFor(loan.scheduleId);
      expect(installments, hasLength(1));
      expect(installments.single.principalPortion, closeTo(1000, 0.01));
    });
  });

  group('LoanRepository.editLoan', () {
    test('records an audit entry per changed field', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
      );

      await repository.editLoan(loan, hasPayments: false, name: 'Car repair loan', notes: 'For Alex');

      expect(loan.editHistory.map((e) => e.field), containsAll(['name', 'notes']));
    });

    test('rejects changing loanAmount once a payment has been recorded', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
      );

      await expectLater(
        repository.editLoan(loan, hasPayments: true, loanAmount: 500),
        throwsA(isA<AppException>()),
      );
    });

    test('allows changing loanAmount before any payment', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
      );

      await repository.editLoan(loan, hasPayments: false, loanAmount: 1500);

      expect(loan.loanAmount, 1500);
    });
  });

  group('LoanRepository.closeLoan / reopenLoan', () {
    test('toggle isClosed and record audit entries', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
      );

      await repository.closeLoan(loan);
      expect(loan.isClosed, true);

      await repository.reopenLoan(loan);
      expect(loan.isClosed, false);
      expect(loan.editHistory, hasLength(2));
    });
  });

  group('Loan.statusGiven', () {
    test('returns closed when isClosed is true regardless of installment state', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2020, 1, 1), // overdue by date
      );
      await repository.closeLoan(loan);

      final installments = await installmentsFor(loan.scheduleId);
      expect(loan.statusGiven(installments).name, 'closed');
    });

    test('returns overdue when the linked installment is overdue and loan is not closed', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2020, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2020, 2, 1),
      );

      final installments = await installmentsFor(loan.scheduleId);
      expect(loan.statusGiven(installments).name, 'overdue');
    });

    test('returns active when the installment is upcoming and loan is not closed', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );

      final installments = await installmentsFor(loan.scheduleId);
      expect(loan.statusGiven(installments).name, 'active');
    });
  });

  group('Soft-delete / restore', () {
    test('soft-deleting a loan does not reverse installment payments; restoring brings it back', () async {
      final loan = await repository.createLoan(
        personId: 'p1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
      );
      final installment = (await installmentsFor(loan.scheduleId)).single;
      await installmentRepositoryFor(loan.scheduleId).applyPayment(installment, 400);

      await repository.softDelete(loan);
      expect((await repository.getAll()).any((l) => l.id == loan.id), false);

      final stillThere = await installmentsFor(loan.scheduleId);
      expect(stillThere.single.amountPaid, 400);

      await repository.restore(loan);
      expect((await repository.getAll()).any((l) => l.id == loan.id), true);
    });
  });
}
