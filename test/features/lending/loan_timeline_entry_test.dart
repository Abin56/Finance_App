import 'package:finance_app/core/models/audit_entry.dart';
import 'package:finance_app/core/payment_schedule/domain/installment.dart';
import 'package:finance_app/core/payment_schedule/domain/installment_payment.dart';
import 'package:finance_app/core/payment_schedule/domain/owner_type.dart';
import 'package:finance_app/features/lending/domain/loan.dart';
import 'package:finance_app/features/lending/domain/loan_direction.dart';
import 'package:finance_app/features/lending/domain/loan_repayment_type.dart';
import 'package:finance_app/features/lending/domain/loan_timeline_entry.dart';
import 'package:flutter_test/flutter_test.dart';

Loan _loan({
  required DateTime createdAt,
  List<AuditEntry> editHistory = const [],
}) {
  return Loan(
    id: 'loan-1',
    loanAmount: 10000,
    loanDate: DateTime(2026, 1, 1),
    repaymentType: LoanRepaymentType.installment,
    scheduleId: 'schedule-1',
    createdAt: createdAt,
    direction: LoanDirection.given,
    installmentFrequency: null,
    installmentCount: 3,
  )..editHistory = editHistory;
}

Installment _installment({required String id, required int sequenceNumber, required double amountDue}) {
  return Installment(
    id: id,
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    sequenceNumber: sequenceNumber,
    dueDate: DateTime(2026, 2, 1),
    amountDue: amountDue,
    createdAt: DateTime(2026, 1, 1),
  );
}

InstallmentPayment _payment({
  required String id,
  required String installmentId,
  required double amount,
  required DateTime createdAt,
  DateTime? deletedAt,
}) {
  return InstallmentPayment(
    id: id,
    installmentId: installmentId,
    scheduleId: 'schedule-1',
    ownerType: OwnerType.loan,
    ownerId: 'loan-1',
    amount: amount,
    date: createdAt,
    createdAt: createdAt,
  )..deletedAt = deletedAt;
}

void main() {
  group('LoanTimelineEntry.build', () {
    test('always includes a Loan Created entry from Loan.createdAt', () {
      final loan = _loan(createdAt: DateTime(2026, 1, 1));

      final entries = LoanTimelineEntry.build(
        loan: loan,
        installments: const [],
        payments: const [],
        deletedPayments: const [],
      );

      expect(entries, hasLength(1));
      expect(entries.single.title, 'Loan Created');
      expect(entries.single.date, DateTime(2026, 1, 1));
    });

    test('a full payment is Payment Recorded; a partial payment is Partial Payment', () {
      final loan = _loan(createdAt: DateTime(2026, 1, 1));
      final installment = _installment(id: 'i1', sequenceNumber: 1, amountDue: 1000);

      final entries = LoanTimelineEntry.build(
        loan: loan,
        installments: [installment],
        payments: [
          _payment(id: 'p1', installmentId: 'i1', amount: 1000, createdAt: DateTime(2026, 2, 1)),
          _payment(id: 'p2', installmentId: 'i1', amount: 400, createdAt: DateTime(2026, 2, 5)),
        ],
        deletedPayments: const [],
      );

      final titles = entries.map((e) => e.title).toList();
      expect(titles, containsAll(['Payment Recorded', 'Partial Payment']));
    });

    test('a deleted payment produces a Payment Deleted entry dated at deletedAt', () {
      final loan = _loan(createdAt: DateTime(2026, 1, 1));
      final installment = _installment(id: 'i1', sequenceNumber: 1, amountDue: 1000);
      final deleted = _payment(
        id: 'p1',
        installmentId: 'i1',
        amount: 1000,
        createdAt: DateTime(2026, 2, 1),
        deletedAt: DateTime(2026, 2, 10),
      );

      final entries = LoanTimelineEntry.build(
        loan: loan,
        installments: [installment],
        payments: const [],
        deletedPayments: [deleted],
      );

      final deletedEntry = entries.firstWhere((e) => e.title == 'Payment Deleted');
      expect(deletedEntry.date, DateTime(2026, 2, 10));
      expect(deletedEntry.subtitle, 'EMI #1');
    });

    test('isClosed audit entries map to Loan Closed / Loan Reopened by direction', () {
      final loan = _loan(
        createdAt: DateTime(2026, 1, 1),
        editHistory: [
          AuditEntry(timestamp: DateTime(2026, 3, 1), field: 'isClosed', oldValue: 'false', newValue: 'true'),
          AuditEntry(timestamp: DateTime(2026, 4, 1), field: 'isClosed', oldValue: 'true', newValue: 'false'),
        ],
      );

      final entries = LoanTimelineEntry.build(
        loan: loan,
        installments: const [],
        payments: const [],
        deletedPayments: const [],
      );

      expect(entries.any((e) => e.title == 'Loan Closed'), isTrue);
      expect(entries.any((e) => e.title == 'Loan Reopened'), isTrue);
    });

    test('editHistory entries for terms/detail fields map to Terms Changed', () {
      final loan = _loan(
        createdAt: DateTime(2026, 1, 1),
        editHistory: [
          AuditEntry(timestamp: DateTime(2026, 3, 1), field: 'loanAmount', oldValue: '10000', newValue: '12000'),
          AuditEntry(timestamp: DateTime(2026, 3, 2), field: 'loanTerms', oldValue: 'a', newValue: 'b'),
        ],
      );

      final entries = LoanTimelineEntry.build(
        loan: loan,
        installments: const [],
        payments: const [],
        deletedPayments: const [],
      );

      final termsEntries = entries.where((e) => e.title == 'Terms Changed').toList();
      expect(termsEntries, hasLength(2));
    });

    test('never fabricates Payment Restored, Loan Restored, or Schedule Re-amortized events', () {
      final loan = _loan(
        createdAt: DateTime(2026, 1, 1),
        editHistory: [
          AuditEntry(timestamp: DateTime(2026, 3, 2), field: 'loanTerms', oldValue: 'a', newValue: 'b'),
        ],
      );
      final installment = _installment(id: 'i1', sequenceNumber: 1, amountDue: 1000);
      final deleted = _payment(
        id: 'p1',
        installmentId: 'i1',
        amount: 1000,
        createdAt: DateTime(2026, 2, 1),
        deletedAt: DateTime(2026, 2, 10),
      );

      final entries = LoanTimelineEntry.build(
        loan: loan,
        installments: [installment],
        payments: const [],
        deletedPayments: [deleted],
      );

      final titles = entries.map((e) => e.title).toSet();
      expect(titles.contains('Payment Restored'), isFalse);
      expect(titles.contains('Loan Restored'), isFalse);
      expect(titles.contains('Schedule Re-amortized'), isFalse);
    });

    test('entries are sorted newest first', () {
      final loan = _loan(createdAt: DateTime(2026, 1, 1));
      final installment = _installment(id: 'i1', sequenceNumber: 1, amountDue: 1000);

      final entries = LoanTimelineEntry.build(
        loan: loan,
        installments: [installment],
        payments: [
          _payment(id: 'p1', installmentId: 'i1', amount: 500, createdAt: DateTime(2026, 2, 1)),
        ],
        deletedPayments: const [],
      );

      final dates = entries.map((e) => e.date).toList();
      final sortedDescending = [...dates]..sort((a, b) => b.compareTo(a));
      expect(dates, sortedDescending);
    });
  });
}
