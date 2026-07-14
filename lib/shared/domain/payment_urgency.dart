import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/payment_schedule/domain/installment_status.dart';
import '../../features/bills/domain/bill_status.dart';
import '../../features/credit_cards/domain/statement_status.dart';

/// Unified payment-timing urgency spanning EMI/Loan installments, Bills, and
/// Credit Card statements — none of which share a status enum. Never
/// stored: always derived from an existing domain status via the
/// `PaymentUrgencyX.from*` mapping functions below, so no domain model
/// gains a new field and no status enum's semantics are duplicated.
///
/// [completed]/gray only reflects a *skipped* payment under each domain's
/// existing status semantics — it is not "instrument fully closed"
/// (that's `EmiStatus.closed`/`LoanStatus.closed`, a different axis).
enum PaymentUrgency { paid, upcoming, dueSoon, overdue, completed }

extension PaymentUrgencyX on PaymentUrgency {
  String get label {
    switch (this) {
      case PaymentUrgency.paid:
        return 'Paid';
      case PaymentUrgency.upcoming:
        return 'Upcoming';
      case PaymentUrgency.dueSoon:
        return 'Due Soon';
      case PaymentUrgency.overdue:
        return 'Overdue';
      case PaymentUrgency.completed:
        return 'Completed';
    }
  }

  Color get color {
    switch (this) {
      case PaymentUrgency.paid:
        return AppColors.success;
      case PaymentUrgency.upcoming:
        return AppColors.info;
      case PaymentUrgency.dueSoon:
        return AppColors.warning;
      case PaymentUrgency.overdue:
        return AppColors.error;
      case PaymentUrgency.completed:
        return AppColors.pending;
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentUrgency.paid:
        return Icons.check_circle_outline_rounded;
      case PaymentUrgency.upcoming:
        return Icons.schedule_rounded;
      case PaymentUrgency.dueSoon:
        return Icons.today_rounded;
      case PaymentUrgency.overdue:
        return Icons.error_outline_rounded;
      case PaymentUrgency.completed:
        return Icons.skip_next_rounded;
    }
  }

  static PaymentUrgency fromInstallmentStatus(InstallmentStatus status) {
    switch (status) {
      case InstallmentStatus.paid:
        return PaymentUrgency.paid;
      case InstallmentStatus.partiallyPaid:
        return PaymentUrgency.dueSoon;
      case InstallmentStatus.skipped:
        return PaymentUrgency.completed;
      case InstallmentStatus.overdue:
        return PaymentUrgency.overdue;
      case InstallmentStatus.upcoming:
        return PaymentUrgency.upcoming;
    }
  }

  static PaymentUrgency fromBillStatus(BillStatus status) {
    switch (status) {
      case BillStatus.paid:
        return PaymentUrgency.paid;
      case BillStatus.partiallyPaid:
        return PaymentUrgency.dueSoon;
      case BillStatus.skipped:
        return PaymentUrgency.completed;
      case BillStatus.overdue:
        return PaymentUrgency.overdue;
      case BillStatus.dueToday:
        return PaymentUrgency.dueSoon;
      case BillStatus.upcoming:
        return PaymentUrgency.upcoming;
    }
  }

  static PaymentUrgency fromStatementStatus(StatementStatus status) {
    switch (status) {
      case StatementStatus.paid:
        return PaymentUrgency.paid;
      case StatementStatus.partiallyPaid:
        return PaymentUrgency.dueSoon;
      case StatementStatus.dueSoon:
        return PaymentUrgency.dueSoon;
      case StatementStatus.overdue:
        return PaymentUrgency.overdue;
      case StatementStatus.pending:
        return PaymentUrgency.upcoming;
    }
  }
}
