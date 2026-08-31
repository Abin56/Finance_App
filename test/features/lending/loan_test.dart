import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_category.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
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

  group('Loan.direction backward compatibility', () {
    test('a Firestore doc with no direction field defaults to given on read', () async {
      final firestore = FakeFirebaseFirestore();
      // Simulate a pre-existing loan document written before `direction`
      // existed — no `direction` key at all, unlike every loan created via
      // `Loan.toFirestore` today.
      await firestore.collection('loans').doc('legacy-loan').set({
        'personId': 'person-1',
        'name': 'Old loan',
        'loanAmount': 2000.0,
        'interest': null,
        'loanDate': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'repaymentType': 'oneTime',
        'dueDate': Timestamp.fromDate(DateTime(2025, 2, 1)),
        'installmentFrequency': null,
        'installmentCount': null,
        'notes': '',
        'scheduleId': 'schedule-legacy',
        'isClosed': false,
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'editHistory': [],
      });

      final snapshot = await firestore.collection('loans').doc('legacy-loan').get();
      final loan = Loan.fromFirestore(snapshot, null);

      expect(loan.direction, LoanDirection.given);
    });

    test('round-trips an explicit taken direction', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('loans').withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          );

      final loan = Loan(
        id: 'loan-taken',
        personId: 'person-1',
        direction: LoanDirection.taken,
        loanAmount: 3000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'schedule-taken',
        createdAt: DateTime(2026, 1, 1),
      );
      await collection.doc(loan.id).set(loan);

      final fetched = (await collection.doc(loan.id).get()).data()!;
      expect(fetched.direction, LoanDirection.taken);
    });

    test('a Loan built with no explicit direction defaults to given', () {
      final loan = Loan(
        id: 'loan-1',
        personId: 'person-1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'schedule-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(loan.direction, LoanDirection.given);
    });
  });

  group('Loan.category backward compatibility', () {
    test('a Firestore doc with no category field defaults to personal, keeping its existing personId', () async {
      final firestore = FakeFirebaseFirestore();
      // Simulate a pre-existing loan document written before `category`/the
      // institution fields existed — every field here matches a real
      // pre-feature doc shape (personId present, no category/institution keys).
      await firestore.collection('loans').doc('legacy-loan').set({
        'personId': 'person-1',
        'direction': 'given',
        'name': 'Old loan',
        'loanAmount': 2000.0,
        'interest': null,
        'loanDate': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'repaymentType': 'oneTime',
        'dueDate': Timestamp.fromDate(DateTime(2025, 2, 1)),
        'installmentFrequency': null,
        'installmentCount': null,
        'notes': '',
        'scheduleId': 'schedule-legacy',
        'isClosed': false,
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'editHistory': [],
      });

      final snapshot = await firestore.collection('loans').doc('legacy-loan').get();
      final loan = Loan.fromFirestore(snapshot, null);

      expect(loan.category, LoanCategory.personal);
      expect(loan.personId, 'person-1');
      expect(loan.institutionName, isNull);
    });

    test('round-trips an institutional loan with null personId and all institution fields', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('loans').withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          );

      final loan = Loan(
        id: 'loan-institutional',
        personId: null,
        category: LoanCategory.institutional,
        institutionName: 'HDFC Bank',
        loanType: 'Home Loan',
        loanNumber: 'HL-12345',
        accountNumber: 'AC-98765',
        branch: 'MG Road',
        direction: LoanDirection.taken,
        loanAmount: 500000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'schedule-institutional',
        createdAt: DateTime(2026, 1, 1),
      );
      await collection.doc(loan.id).set(loan);

      final fetched = (await collection.doc(loan.id).get()).data()!;
      expect(fetched.personId, isNull);
      expect(fetched.category, LoanCategory.institutional);
      expect(fetched.institutionName, 'HDFC Bank');
      expect(fetched.loanType, 'Home Loan');
      expect(fetched.loanNumber, 'HL-12345');
      expect(fetched.accountNumber, 'AC-98765');
      expect(fetched.branch, 'MG Road');
    });

    test('a Loan built with no explicit category defaults to personal', () {
      final loan = Loan(
        id: 'loan-1',
        personId: 'person-1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'schedule-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(loan.category, LoanCategory.personal);
    });
  });

  group('Loan.payerPersonId', () {
    test('defaults to null when not set, and a Firestore doc with no payerPersonId field round-trips as null', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('loans').withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          );

      final loan = Loan(
        id: 'loan-no-payer',
        personId: 'person-1',
        loanAmount: 1000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'schedule-1',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(loan.payerPersonId, isNull);

      await collection.doc(loan.id).set(loan);
      final fetched = (await collection.doc(loan.id).get()).data()!;
      expect(fetched.payerPersonId, isNull);
    });

    test('round-trips an explicit payerPersonId, distinct from personId — covers "I took a bank loan, a friend pays it"', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('loans').withConverter<Loan>(
            fromFirestore: Loan.fromFirestore,
            toFirestore: (l, _) => l.toFirestore(),
          );

      final loan = Loan(
        id: 'loan-with-payer',
        personId: null,
        category: LoanCategory.institutional,
        institutionName: 'HDFC Bank',
        payerPersonId: 'friend-1',
        loanAmount: 50000,
        loanDate: DateTime(2026, 1, 1),
        repaymentType: LoanRepaymentType.oneTime,
        dueDate: DateTime(2026, 2, 1),
        scheduleId: 'schedule-2',
        createdAt: DateTime(2026, 1, 1),
      );
      await collection.doc(loan.id).set(loan);

      final fetched = (await collection.doc(loan.id).get()).data()!;
      expect(fetched.personId, isNull);
      expect(fetched.payerPersonId, 'friend-1');
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
