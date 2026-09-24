import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import 'loan.dart';

/// A single, honestly-derived event in a loan's history — never a guess or a
/// reconstruction. Every entry traces back to a real timestamp already
/// stored somewhere: [Loan.createdAt], an [InstallmentPayment]'s own
/// `createdAt`/`deletedAt`, or one of [Loan]'s `editHistory` entries.
///
/// Deliberately excluded, because nothing in the data model can support them
/// without fabrication: "Payment Restored" and "Loan Restored" (soft-delete
/// restore leaves no trace — `restoreFromTrash()` simply nulls `deletedAt`),
/// and "Schedule Re-amortized" as a distinct event from "Terms Changed"
/// (`LoanRepository.editLoanTerms` records both facts under one composite
/// `loanTerms` audit entry, so they aren't separable after the fact).
class LoanTimelineEntry {
  const LoanTimelineEntry({
    required this.date,
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
  });

  final DateTime date;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;

  /// Loan-level fields whose `editHistory` entries are real, reliable
  /// evidence that "something about this loan's terms changed" — grouped
  /// under one "Terms Changed" event type rather than a field-by-field
  /// taxonomy, since `loanTerms` itself is already a composite value that
  /// can't be split into rate/frequency/count sub-events.
  static const _termsFields = {
    'loanTerms',
    'loanDate',
    'loanAmount',
    'name',
    'payerPersonId',
    'notes',
    'institutionName',
    'loanType',
    'loanNumber',
    'accountNumber',
    'branch',
  };

  /// Builds a loan's full timeline, newest first, from data already loaded
  /// by the caller — no I/O, mirrors `LoanFinancialSummary.from`. [payments]
  /// and [deletedPayments] should cover every installment on the loan's
  /// schedule (not just one), typically gathered by
  /// `loanTimelineProvider`'s fan-out over each installment's payment
  /// subcollection and trash.
  static List<LoanTimelineEntry> build({
    required Loan loan,
    required List<Installment> installments,
    required List<InstallmentPayment> payments,
    required List<InstallmentPayment> deletedPayments,
  }) {
    final installmentById = {for (final i in installments) i.id: i};
    final entries = <LoanTimelineEntry>[
      LoanTimelineEntry(
        date: loan.createdAt,
        icon: Icons.add_circle_outline_rounded,
        title: 'Loan Created',
        color: AppColors.info,
      ),
      for (final payment in payments)
        LoanTimelineEntry(
          date: payment.createdAt,
          icon: Icons.payments_outlined,
          title: (installmentById[payment.installmentId]?.amountDue ?? payment.amount) > payment.amount
              ? 'Partial Payment'
              : 'Payment Recorded',
          subtitle: 'EMI #${installmentById[payment.installmentId]?.sequenceNumber ?? '?'}',
          color: AppColors.success,
        ),
      for (final payment in deletedPayments)
        LoanTimelineEntry(
          date: payment.deletedAt ?? payment.createdAt,
          icon: Icons.delete_outline_rounded,
          title: 'Payment Deleted',
          subtitle: 'EMI #${installmentById[payment.installmentId]?.sequenceNumber ?? '?'}',
          color: AppColors.error,
        ),
      for (final entry in loan.editHistory)
        if (entry.field == 'isClosed')
          LoanTimelineEntry(
            date: entry.timestamp,
            icon: entry.newValue == 'true' ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
            title: entry.newValue == 'true' ? 'Loan Closed' : 'Loan Reopened',
            color: entry.newValue == 'true' ? AppColors.pending : AppColors.info,
          )
        else if (_termsFields.contains(entry.field))
          LoanTimelineEntry(
            date: entry.timestamp,
            icon: Icons.edit_outlined,
            title: 'Terms Changed',
            subtitle: '${entry.field}: ${entry.oldValue} → ${entry.newValue}',
            color: AppColors.warning,
          ),
    ];

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }
}
