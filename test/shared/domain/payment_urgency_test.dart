import 'package:finance_app/core/payment_schedule/domain/installment_status.dart';
import 'package:finance_app/features/bills/domain/bill_status.dart';
import 'package:finance_app/features/credit_cards/domain/statement_status.dart';
import 'package:finance_app/shared/domain/payment_urgency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentUrgencyX.fromInstallmentStatus', () {
    final expected = {
      InstallmentStatus.paid: PaymentUrgency.paid,
      InstallmentStatus.partiallyPaid: PaymentUrgency.dueSoon,
      InstallmentStatus.skipped: PaymentUrgency.completed,
      InstallmentStatus.overdue: PaymentUrgency.overdue,
      InstallmentStatus.upcoming: PaymentUrgency.upcoming,
    };

    for (final entry in expected.entries) {
      test('${entry.key} maps to ${entry.value}', () {
        expect(PaymentUrgencyX.fromInstallmentStatus(entry.key), entry.value);
      });
    }
  });

  group('PaymentUrgencyX.fromBillStatus', () {
    final expected = {
      BillStatus.paid: PaymentUrgency.paid,
      BillStatus.partiallyPaid: PaymentUrgency.dueSoon,
      BillStatus.skipped: PaymentUrgency.completed,
      BillStatus.overdue: PaymentUrgency.overdue,
      BillStatus.dueToday: PaymentUrgency.dueSoon,
      BillStatus.upcoming: PaymentUrgency.upcoming,
    };

    for (final entry in expected.entries) {
      test('${entry.key} maps to ${entry.value}', () {
        expect(PaymentUrgencyX.fromBillStatus(entry.key), entry.value);
      });
    }
  });

  group('PaymentUrgencyX.fromStatementStatus', () {
    final expected = {
      StatementStatus.paid: PaymentUrgency.paid,
      StatementStatus.partiallyPaid: PaymentUrgency.dueSoon,
      StatementStatus.dueSoon: PaymentUrgency.dueSoon,
      StatementStatus.overdue: PaymentUrgency.overdue,
      StatementStatus.pending: PaymentUrgency.upcoming,
    };

    for (final entry in expected.entries) {
      test('${entry.key} maps to ${entry.value}', () {
        expect(PaymentUrgencyX.fromStatementStatus(entry.key), entry.value);
      });
    }
  });
}
