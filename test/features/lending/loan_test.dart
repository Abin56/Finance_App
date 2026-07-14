import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_interest.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/domain/loan_status.dart';
import 'package:flutter_test/flutter_test.dart';

Installment _installment({required DateTime dueDate, double amountDue = 100, double amountPaid = 0}) {
  return Installment(
    id: 'i1',
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    sequenceNumber: 1,
    dueDate: dueDate,
    amountDue: amountDue,
    amountPaid: amountPaid,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('Loan.fromFirestore / toFirestore', () {
    test('round-trips every field including installment fields and interest map', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('loans').withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          );

      final loan = Loan(
        id: 'loan-1',
        personId: 'person-1',
        name: 'Car repair',
        loanAmount: 5000,
        interest: const LoanInterest(type: InterestType.reducingBalance, ratePercent: 10, period: InterestPeriod.yearly),
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.installment,
        installmentFrequency: null,
        installmentCount: 6,
        notes: 'For Alex',
        scheduleId: 'schedule-1',
        createdAt: DateTime(2026, 1, 1),
      );
      await collection.doc(loan.id).set(loan);

      final fetched = (await collection.doc(loan.id).get()).data()!;

      expect(fetched.name, 'Car repair');
      expect(fetched.loanAmount, 5000);
      expect(fetched.interest?.type, InterestType.reducingBalance);
      expect(fetched.interest?.ratePercent, 10);
      expect(fetched.interest?.period, InterestPeriod.yearly);
      expect(fetched.repaymentType, LoanRepaymentType.installment);
      expect(fetched.installmentCount, 6);
      expect(fetched.scheduleId, 'schedule-1');
    });

    test('round-trips a loan with no interest', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('loans').withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          );

      final loan = Loan(
        id: 'loan-2',
        personId: 'person-1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'schedule-2',
        createdAt: DateTime(2026, 1, 1),
      );
      await collection.doc(loan.id).set(loan);

      final fetched = (await collection.doc(loan.id).get()).data()!;
      expect(fetched.interest, isNull);
      expect(fetched.dueDate, DateTime(2026, 2, 1));
      expect(fetched.installmentFrequency, isNull);
      expect(fetched.installmentCount, isNull);
    });
  });

  group('Loan.statusGiven', () {
    Loan buildLoan({bool isClosed = false}) => Loan(
          id: 'loan-1',
          personId: 'person-1',
          loanAmount: 1000,
          loanDate: DateTime(2026, 1, 1),
          repaymentType: LoanRepaymentType.oneTime,
          dueDate: DateTime(2026, 2, 1),
          scheduleId: 'schedule-1',
          createdAt: DateTime(2026, 1, 1),
          isClosed: isClosed,
        );

    test('returns closed when isClosed is true', () {
      final loan = buildLoan(isClosed: true);
      final installments = [_installment(dueDate: DateTime.now().subtract(const Duration(days: 10)))];

      expect(loan.statusGiven(installments), LoanStatus.closed);
    });

    test('returns overdue when any installment is overdue and loan is not closed', () {
      final loan = buildLoan();
      final installments = [_installment(dueDate: DateTime.now().subtract(const Duration(days: 10)))];
      expect(installments.single.status, InstallmentStatus.overdue);

      expect(loan.statusGiven(installments), LoanStatus.overdue);
    });

    test('returns active when no installment is overdue and loan is not closed', () {
      final loan = buildLoan();
      final installments = [_installment(dueDate: DateTime.now().add(const Duration(days: 10)))];

      expect(loan.statusGiven(installments), LoanStatus.active);
    });
  });
}
