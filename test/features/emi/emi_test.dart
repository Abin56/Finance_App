import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:finance_app/features/emi/domain/emi.dart';
import 'package:finance_app/features/emi/domain/emi_installment_display.dart';
import 'package:finance_app/features/emi/domain/emi_interest.dart';
import 'package:finance_app/features/emi/domain/emi_loan_type.dart';
import 'package:finance_app/features/emi/domain/emi_status.dart';
import 'package:flutter_test/flutter_test.dart';

Installment _installment({required DateTime dueDate, double amountDue = 100, double amountPaid = 0}) {
  return Installment(
    id: 'i1',
    scheduleId: 'schedule-1',
    ownerType: OwnerType.emi,
    ownerId: 'emi-1',
    sequenceNumber: 1,
    dueDate: dueDate,
    amountDue: amountDue,
    amountPaid: amountPaid,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('Emi.fromFirestore / toFirestore', () {
    test('round-trips every field including nullable lenderName/categoryId/interest', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('emis').withConverter<Emi>(
            fromFirestore: Emi.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );

      final emi = Emi(
        id: 'emi-1',
        name: 'Car loan',
        lenderName: 'HDFC Bank',
        categoryId: 'cat-1',
        principalAmount: 500000,
        interest: const EmiInterest(type: InterestType.reducingBalance, ratePercent: 9, period: InterestPeriod.yearly),
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 60,
        endDate: DateTime(2031, 1, 1),
        notes: 'Sedan',
        scheduleId: 'schedule-1',
        createdAt: DateTime(2026, 1, 1),
        loanNumber: 'LN12345',
        loanType: EmiLoanType.vehicle,
        branch: 'Downtown',
        customerId: 'CUST-9',
        sanctionDate: DateTime(2025, 12, 15),
        disbursementDate: DateTime(2025, 12, 20),
        processingFee: 5000,
        insuranceAmount: 2000,
        extraCharges: 500,
        foreclosureAmount: 10000,
        prepaymentCharges: 1500,
        isAutoDebitEnabled: true,
        autoDebitAccount: 'XXXX1234',
        isDefaulted: false,
        linkedCreditCardId: 'card-1',
        dueDayOfMonth: 5,
      );
      await collection.doc(emi.id).set(emi);

      final fetched = (await collection.doc(emi.id).get()).data()!;
      expect(fetched.name, 'Car loan');
      expect(fetched.lenderName, 'HDFC Bank');
      expect(fetched.categoryId, 'cat-1');
      expect(fetched.principalAmount, 500000);
      expect(fetched.interest?.type, InterestType.reducingBalance);
      expect(fetched.interest?.ratePercent, 9);
      expect(fetched.installmentFrequency, ScheduleType.monthly);
      expect(fetched.installmentCount, 60);
      expect(fetched.endDate, DateTime(2031, 1, 1));
      expect(fetched.scheduleId, 'schedule-1');
      expect(fetched.loanNumber, 'LN12345');
      expect(fetched.loanType, EmiLoanType.vehicle);
      expect(fetched.branch, 'Downtown');
      expect(fetched.customerId, 'CUST-9');
      expect(fetched.sanctionDate, DateTime(2025, 12, 15));
      expect(fetched.disbursementDate, DateTime(2025, 12, 20));
      expect(fetched.processingFee, 5000);
      expect(fetched.insuranceAmount, 2000);
      expect(fetched.extraCharges, 500);
      expect(fetched.foreclosureAmount, 10000);
      expect(fetched.prepaymentCharges, 1500);
      expect(fetched.isAutoDebitEnabled, true);
      expect(fetched.autoDebitAccount, 'XXXX1234');
      expect(fetched.linkedCreditCardId, 'card-1');
      expect(fetched.dueDayOfMonth, 5);
    });

    test('defaults linkedCreditCardId and dueDayOfMonth to null for a document written before these fields existed',
        () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('emis').withConverter<Emi>(
            fromFirestore: Emi.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );
      await collection.doc('emi-legacy').set(
            Emi(
              id: 'emi-legacy',
              name: 'Legacy EMI',
              principalAmount: 1000,
              startDate: DateTime(2026, 1, 1),
              installmentFrequency: ScheduleType.monthly,
              installmentCount: 4,
              endDate: DateTime(2026, 4, 1),
              scheduleId: 'schedule-legacy',
              createdAt: DateTime(2026, 1, 1),
            ),
          );

      final fetched = (await collection.doc('emi-legacy').get()).data()!;
      expect(fetched.linkedCreditCardId, isNull);
      expect(fetched.dueDayOfMonth, isNull);
    });

    test('round-trips an EMI with no interest and no lender/category', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('emis').withConverter<Emi>(
            fromFirestore: Emi.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );

      final emi = Emi(
        id: 'emi-2',
        name: 'Phone EMI',
        principalAmount: 20000,
        startDate: DateTime(2026, 1, 1),
        installmentFrequency: ScheduleType.monthly,
        installmentCount: 6,
        endDate: DateTime(2026, 6, 1),
        scheduleId: 'schedule-2',
        createdAt: DateTime(2026, 1, 1),
      );
      await collection.doc(emi.id).set(emi);

      final fetched = (await collection.doc(emi.id).get()).data()!;
      expect(fetched.interest, isNull);
      expect(fetched.lenderName, isNull);
      expect(fetched.categoryId, isNull);
      expect(fetched.loanType, EmiLoanType.other);
      expect(fetched.processingFee, 0);
      expect(fetched.insuranceAmount, 0);
      expect(fetched.extraCharges, 0);
      expect(fetched.isAutoDebitEnabled, false);
      expect(fetched.isDefaulted, false);
    });

    test('parses a pre-existing document that has none of the new loan-management fields', () async {
      final firestore = FakeFirebaseFirestore();
      final collection = firestore.collection('emis').withConverter<Emi>(
            fromFirestore: Emi.fromFirestore,
            toFirestore: (e, _) => e.toFirestore(),
          );

      // Simulates a document written before this upgrade — no loanType,
      // loanNumber, fees, or defaulted flag keys at all.
      await collection.doc('emi-legacy').set(
            Emi(
              id: 'emi-legacy',
              name: 'Legacy EMI',
              principalAmount: 1000,
              startDate: DateTime(2026, 1, 1),
              installmentFrequency: ScheduleType.monthly,
              installmentCount: 4,
              endDate: DateTime(2026, 4, 1),
              scheduleId: 'schedule-legacy',
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      await firestore.collection('emis').doc('emi-legacy').update({
        'loanNumber': FieldValue.delete(),
        'loanType': FieldValue.delete(),
        'processingFee': FieldValue.delete(),
        'insuranceAmount': FieldValue.delete(),
        'extraCharges': FieldValue.delete(),
        'isAutoDebitEnabled': FieldValue.delete(),
        'isDefaulted': FieldValue.delete(),
      });

      final fetched = (await collection.doc('emi-legacy').get()).data()!;
      expect(fetched.loanType, EmiLoanType.other);
      expect(fetched.processingFee, 0);
      expect(fetched.insuranceAmount, 0);
      expect(fetched.extraCharges, 0);
      expect(fetched.isAutoDebitEnabled, false);
      expect(fetched.isDefaulted, false);
    });
  });

  group('Emi.statusGiven', () {
    Emi buildEmi({bool isClosed = false, bool isDefaulted = false}) => Emi(
          id: 'emi-1',
          name: 'Phone EMI',
          principalAmount: 1000,
          startDate: DateTime(2026, 1, 1),
          installmentFrequency: ScheduleType.monthly,
          installmentCount: 4,
          endDate: DateTime(2026, 4, 1),
          scheduleId: 'schedule-1',
          createdAt: DateTime(2026, 1, 1),
          isClosed: isClosed,
          isDefaulted: isDefaulted,
        );

    test('returns closed when isClosed is true', () {
      final emi = buildEmi(isClosed: true);
      final installments = [_installment(dueDate: DateTime.now().subtract(const Duration(days: 10)))];

      expect(emi.statusGiven(installments), EmiStatus.closed);
    });

    test('returns defaulted when isDefaulted is true and not closed', () {
      final emi = buildEmi(isDefaulted: true);
      final installments = [_installment(dueDate: DateTime.now().subtract(const Duration(days: 10)))];

      expect(emi.statusGiven(installments), EmiStatus.defaulted);
    });

    test('closed takes precedence over defaulted', () {
      final emi = buildEmi(isClosed: true, isDefaulted: true);
      final installments = [_installment(dueDate: DateTime.now().subtract(const Duration(days: 10)))];

      expect(emi.statusGiven(installments), EmiStatus.closed);
    });

    test('returns overdue when any installment is overdue and not closed', () {
      final emi = buildEmi();
      final installments = [_installment(dueDate: DateTime.now().subtract(const Duration(days: 10)))];

      expect(emi.statusGiven(installments), EmiStatus.overdue);
    });

    test('returns active when no installment is overdue and not closed', () {
      final emi = buildEmi();
      final installments = [_installment(dueDate: DateTime.now().add(const Duration(days: 10)))];

      expect(emi.statusGiven(installments), EmiStatus.active);
    });
  });

  group('emiInstallmentStatusLabel', () {
    test('relabels upcoming as Unpaid when due date is in the current month', () {
      final dueThisMonth = DateTime(DateTime.now().year, DateTime.now().month, 28);
      expect(emiInstallmentStatusLabel(InstallmentStatus.upcoming, dueThisMonth), 'Unpaid');
    });

    test('keeps upcoming as Upcoming when due date is in a future month', () {
      final now = DateTime.now();
      final dueNextMonth = DateTime(now.year, now.month + 2, 1);
      expect(emiInstallmentStatusLabel(InstallmentStatus.upcoming, dueNextMonth), 'Upcoming');
    });

    test('overdue stays Missed Payment regardless of month', () {
      final dueThisMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
      expect(emiInstallmentStatusLabel(InstallmentStatus.overdue, dueThisMonth), 'Missed Payment');
    });

    test('paid stays Paid', () {
      final dueThisMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
      expect(emiInstallmentStatusLabel(InstallmentStatus.paid, dueThisMonth), 'Paid');
    });
  });
}
