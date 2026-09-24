import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';

/// How one [LoanPaymentHistoryEntry] reads in the timeline — a payment's own
/// circumstances at the time it was made, distinct from
/// `Installment.status` (which is the installment's standing today).
enum LoanPaymentHistoryStatus { paid, partial, advance, overdue }

extension LoanPaymentHistoryStatusX on LoanPaymentHistoryStatus {
  String get label {
    switch (this) {
      case LoanPaymentHistoryStatus.paid:
        return 'Paid';
      case LoanPaymentHistoryStatus.partial:
        return 'Partial';
      case LoanPaymentHistoryStatus.advance:
        return 'Paid Early';
      case LoanPaymentHistoryStatus.overdue:
        return 'Paid Late';
    }
  }

  Color get color {
    switch (this) {
      case LoanPaymentHistoryStatus.paid:
        return AppColors.success;
      case LoanPaymentHistoryStatus.partial:
        return AppColors.warning;
      case LoanPaymentHistoryStatus.advance:
        return AppColors.info;
      case LoanPaymentHistoryStatus.overdue:
        return AppColors.error;
    }
  }

  IconData get icon {
    switch (this) {
      case LoanPaymentHistoryStatus.paid:
        return Icons.check_circle_outline_rounded;
      case LoanPaymentHistoryStatus.partial:
        return Icons.incomplete_circle_rounded;
      case LoanPaymentHistoryStatus.advance:
        return Icons.fast_forward_rounded;
      case LoanPaymentHistoryStatus.overdue:
        return Icons.error_outline_rounded;
    }
  }
}

/// One real [InstallmentPayment] against a loan, in loan-wide chronological
/// order — built by `loanPaymentHistoryProvider`, which folds every
/// installment's payments together to compute [remainingBalanceAfter]
/// against the whole loan (not just the one installment the payment landed
/// on). Never reconstructed from `Installment.amountPaid` — each entry
/// mirrors one actual payment record, so multiple partial payments against
/// the same installment stay separate, and a soft-deleted payment simply
/// isn't in the list (excluded upstream by `installmentPaymentsStreamProvider`).
class LoanPaymentHistoryEntry {
  const LoanPaymentHistoryEntry({
    required this.payment,
    required this.installmentSequenceNumber,
    required this.status,
    required this.remainingBalanceAfter,
  });

  final InstallmentPayment payment;
  final int installmentSequenceNumber;
  final LoanPaymentHistoryStatus status;

  /// The loan's total outstanding immediately after this payment, folding
  /// every payment up to and including this one — display-only, computed
  /// from the same payment records `LoanFinancialSummary` uses elsewhere on
  /// the screen, never a second source of truth for the loan's current
  /// outstanding balance.
  final double remainingBalanceAfter;

  DateTime get date => payment.date;
  double get amount => payment.amount;
  String get note => payment.note;

  /// Who actually paid this specific payment — `null` means the account
  /// owner ("You"). Distinct from `Loan.payerPersonId` (the loan's
  /// configured default EMI payer), which only describes who is *expected*
  /// to pay, not who paid any one payment.
  String? get payerPersonId => payment.payerPersonId;

  static LoanPaymentHistoryStatus statusFor(InstallmentPayment payment, Installment installment) {
    if (payment.date.isBefore(installment.dueDate)) return LoanPaymentHistoryStatus.advance;
    if (payment.amount < installment.amountDue) return LoanPaymentHistoryStatus.partial;
    if (installment.dueDate.isBefore(payment.date)) return LoanPaymentHistoryStatus.overdue;
    return LoanPaymentHistoryStatus.paid;
  }
}
