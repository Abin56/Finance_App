import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import 'emi_payment_breakdown.dart';

/// How one [EmiPaymentHistoryEntry] should read in the timeline — distinct
/// from [InstallmentStatus] (which describes an installment's current
/// standing) since a single payment's label is about that payment's
/// circumstances at the time it was made, not the installment's state today.
enum EmiPaymentHistoryStatus { paid, partial, advance, overdue, skipped }

extension EmiPaymentHistoryStatusX on EmiPaymentHistoryStatus {
  String get label {
    switch (this) {
      case EmiPaymentHistoryStatus.paid:
        return 'Paid';
      case EmiPaymentHistoryStatus.partial:
        return 'Partial';
      case EmiPaymentHistoryStatus.advance:
        return 'Paid Early';
      case EmiPaymentHistoryStatus.overdue:
        return 'Missed Payment';
      case EmiPaymentHistoryStatus.skipped:
        return 'Skipped';
    }
  }

  Color get color {
    switch (this) {
      case EmiPaymentHistoryStatus.paid:
        return AppColors.success;
      case EmiPaymentHistoryStatus.partial:
        return AppColors.warning;
      case EmiPaymentHistoryStatus.advance:
        return AppColors.info;
      case EmiPaymentHistoryStatus.overdue:
        return AppColors.error;
      case EmiPaymentHistoryStatus.skipped:
        return AppColors.pending;
    }
  }

  IconData get icon {
    switch (this) {
      case EmiPaymentHistoryStatus.paid:
        return Icons.check_circle_outline_rounded;
      case EmiPaymentHistoryStatus.partial:
        return Icons.incomplete_circle_rounded;
      case EmiPaymentHistoryStatus.advance:
        return Icons.fast_forward_rounded;
      case EmiPaymentHistoryStatus.overdue:
        return Icons.error_outline_rounded;
      case EmiPaymentHistoryStatus.skipped:
        return Icons.skip_next_rounded;
    }
  }
}

/// One line in an EMI's full payment timeline — either an actual
/// [InstallmentPayment] or a skipped installment with no payment. Built by
/// `emiPaymentHistoryProvider`, which folds every installment's payments in
/// chronological order to compute [remainingBalanceAfter] against the whole
/// schedule (not just the one installment the payment landed on), since the
/// spec asks for "remaining balance after payment" at the EMI level.
class EmiPaymentHistoryEntry {
  const EmiPaymentHistoryEntry({
    required this.date,
    required this.amount,
    required this.note,
    required this.status,
    required this.remainingBalanceAfter,
    required this.installmentSequenceNumber,
    this.payment,
    this.breakdown,
  });

  final DateTime date;
  final double amount;
  final String note;
  final EmiPaymentHistoryStatus status;
  final double remainingBalanceAfter;
  final int installmentSequenceNumber;

  /// Null for a skipped-installment entry, which has no underlying payment.
  final InstallmentPayment? payment;

  /// The detailed charge breakdown for [payment], if one was recorded (only
  /// payments made through `RecordEmiPaymentSheet` create one) — null for
  /// older payments, payments recorded via the multi-payment sheet, or a
  /// skipped-installment entry. The UI falls back to showing just [amount]
  /// when this is null.
  final EmiPaymentBreakdown? breakdown;

  /// "Paid by X" is embedded in [note] (see `RecordEmiPaymentSheet._resolveNote`)
  /// rather than a structured field — extracted here so the timeline can
  /// show it as its own line without a schema change.
  String? get paidBy {
    const prefix = 'Paid by ';
    if (note.startsWith(prefix)) return note.substring(prefix.length);
    return null;
  }

  static EmiPaymentHistoryStatus statusFor(InstallmentPayment payment, Installment installment) {
    if (payment.date.isBefore(installment.dueDate)) return EmiPaymentHistoryStatus.advance;
    if (payment.amount < installment.amountDue) return EmiPaymentHistoryStatus.partial;
    if (installment.dueDate.isBefore(payment.date)) return EmiPaymentHistoryStatus.overdue;
    return EmiPaymentHistoryStatus.paid;
  }
}
