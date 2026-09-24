import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/lending/domain/loan_financial_summary.dart';
import 'package:flutter_test/flutter_test.dart';

Installment _installment({
  required String id,
  required int sequenceNumber,
  required DateTime dueDate,
  required double amountDue,
  double amountPaid = 0,
  bool isSkipped = false,
  double? principalPortion,
  double? interestPortion,
}) {
  return Installment(
    id: id,
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    sequenceNumber: sequenceNumber,
    dueDate: dueDate,
    amountDue: amountDue,
    amountPaid: amountPaid,
    isSkipped: isSkipped,
    principalPortion: principalPortion,
    interestPortion: interestPortion,
    createdAt: DateTime(2026, 1, 1),
  );
}

final _yesterday = DateTime.now().subtract(const Duration(days: 1));
final _tomorrow = DateTime.now().add(const Duration(days: 1));

void main() {
  group('LoanFinancialSummary.from', () {
    test('example 1: single one-time installment, partial payment', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _tomorrow, amountDue: 65000, amountPaid: 10000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 65000);

      expect(summary.totalPaid, 10000);
      expect(summary.totalScheduledPayable, 65000);
      expect(summary.outstanding, 55000);
    });

    test('example 2: three installments, two payments spanning them', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 5000, amountPaid: 5000),
        _installment(id: 'i2', sequenceNumber: 2, dueDate: _tomorrow, amountDue: 5000, amountPaid: 2000),
        _installment(id: 'i3', sequenceNumber: 3, dueDate: _tomorrow, amountDue: 5000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 15000);

      expect(summary.totalPaid, 7000);
      expect(summary.outstanding, 8000);
      expect(summary.paidInstallments, 1);
      expect(summary.partialInstallments, 1);
      expect(summary.remainingInstallments, 2);
    });

    test('example 3: no payments at all', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _tomorrow, amountDue: 5000),
        _installment(id: 'i2', sequenceNumber: 2, dueDate: _tomorrow, amountDue: 5000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 10000);

      expect(summary.totalPaid, 0);
      expect(summary.outstanding, summary.totalScheduledPayable);
      expect(summary.outstanding, 10000);
    });

    test('example 4: fully paid loan', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 5000, amountPaid: 5000),
        _installment(id: 'i2', sequenceNumber: 2, dueDate: _yesterday, amountDue: 5000, amountPaid: 5000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 10000);

      expect(summary.totalPaid, summary.totalScheduledPayable);
      expect(summary.outstanding, 0);
      expect(summary.paidInstallments, 2);
      expect(summary.remainingInstallments, 0);
      expect(summary.nextInstallment, isNull);
      expect(summary.progress, 1.0);
    });

    test('zero-interest loan: entire payment counts as principal', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _tomorrow, amountDue: 1000, amountPaid: 400),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 1000);

      expect(summary.totalScheduledInterest, 0);
      expect(summary.interestPaid, 0);
      expect(summary.principalPaid, 400);
      expect(summary.principalRemaining, 600);
      expect(summary.interestRemaining, 0);
    });

    test('interest-bearing loan: payment credited interest-first then principal', () {
      // interestPortion 100, principalPortion 900 => amountDue 1000.
      final installments = [
        _installment(
          id: 'i1',
          sequenceNumber: 1,
          dueDate: _tomorrow,
          amountDue: 1000,
          amountPaid: 50,
          principalPortion: 900,
          interestPortion: 100,
        ),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 900);

      // 50 paid, all goes to interest first (interest portion is 100, not yet exhausted).
      expect(summary.interestPaid, 50);
      expect(summary.principalPaid, 0);

      final installmentsFull = [
        _installment(
          id: 'i1',
          sequenceNumber: 1,
          dueDate: _tomorrow,
          amountDue: 1000,
          amountPaid: 300,
          principalPortion: 900,
          interestPortion: 100,
        ),
      ];
      final summaryFull = LoanFinancialSummary.from(installments: installmentsFull, originalPrincipal: 900);
      // interest portion (100) fully covered, remaining 200 goes to principal.
      expect(summaryFull.interestPaid, 100);
      expect(summaryFull.principalPaid, 200);
    });

    test('overdue installment contributes to overdueInstallments/overdueAmount', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 3000),
        _installment(id: 'i2', sequenceNumber: 2, dueDate: _tomorrow, amountDue: 3000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 6000);

      expect(summary.overdueInstallments, 1);
      expect(summary.overdueAmount, 3000);
    });

    test('a partially-paid overdue installment is never double-counted as overdue', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 3000, amountPaid: 500),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 3000);

      expect(installments.first.status, InstallmentStatus.partiallyPaid);
      expect(summary.overdueInstallments, 0);
      expect(summary.overdueAmount, 0);
      expect(summary.partialInstallments, 1);
    });

    test('skipped installments are excluded from next/remaining but still count toward totalPaid', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 1000, amountPaid: 1000),
        _installment(id: 'i2', sequenceNumber: 2, dueDate: _yesterday, amountDue: 1000, isSkipped: true, amountPaid: 200),
        _installment(id: 'i3', sequenceNumber: 3, dueDate: _tomorrow, amountDue: 1000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 3000);

      expect(summary.totalPaid, 1200);
      expect(summary.nextInstallment?.id, 'i3');
      expect(summary.overdueInstallments, 0);
    });

    test('lump-sum settlement fully covering multiple installments', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 2000, amountPaid: 2000),
        _installment(id: 'i2', sequenceNumber: 2, dueDate: _tomorrow, amountDue: 2000, amountPaid: 2000),
        _installment(id: 'i3', sequenceNumber: 3, dueDate: _tomorrow, amountDue: 2000, amountPaid: 500),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 6000);

      expect(summary.totalPaid, 4500);
      expect(summary.paidInstallments, 2);
      expect(summary.partialInstallments, 1);
      expect(summary.nextInstallment?.id, 'i3');
    });

    test('closed/fully-settled loan with no remaining installments has null nextInstallment', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 1000, amountPaid: 1000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 1000);

      expect(summary.nextInstallment, isNull);
      expect(summary.remainingInstallments, 0);
      expect(summary.progress, 1.0);
    });

    test('one-time loan: single installment behaves like an installment loan of length 1', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _tomorrow, amountDue: 5000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 5000);

      expect(summary.nextInstallment?.id, 'i1');
      expect(summary.remainingInstallments, 1);
      expect(summary.outstanding, 5000);
    });

    test('rounding: fractional amounts sum without drifting due to clamping', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 3333.33, amountPaid: 3333.33),
        _installment(id: 'i2', sequenceNumber: 2, dueDate: _tomorrow, amountDue: 3333.33),
        _installment(id: 'i3', sequenceNumber: 3, dueDate: _tomorrow, amountDue: 3333.34),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 10000);

      expect(summary.totalScheduledPayable, closeTo(10000, 0.001));
      expect(summary.totalPaid, closeTo(3333.33, 0.001));
      expect(summary.outstanding, closeTo(6666.67, 0.001));
    });

    test('outstanding never goes negative even if amountPaid overshoots amountDue', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _yesterday, amountDue: 1000, amountPaid: 1500),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 1000);

      expect(summary.outstanding, 0);
      expect(summary.principalRemaining, 0);
    });

    test('no installments at all: defensive defaults', () {
      final summary = LoanFinancialSummary.from(installments: const [], originalPrincipal: 0);

      expect(summary.totalPaid, 0);
      expect(summary.totalScheduledPayable, 0);
      expect(summary.outstanding, 0);
      expect(summary.nextInstallment, isNull);
      expect(summary.progress, 1.0);
    });

    test('progress is the paid fraction of scheduled payable, clamped to [0,1]', () {
      final installments = [
        _installment(id: 'i1', sequenceNumber: 1, dueDate: _tomorrow, amountDue: 4000, amountPaid: 1000),
      ];

      final summary = LoanFinancialSummary.from(installments: installments, originalPrincipal: 4000);

      expect(summary.progress, 0.25);
    });
  });
}
