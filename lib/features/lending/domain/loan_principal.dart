import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_payment.dart';
import '../../../core/payment_schedule/domain/payment_allocation_type.dart';

/// Total extra principal paid on a loan, derived from its persisted
/// [InstallmentPayment] records — never a stored running total, so a reversal
/// (which soft-deletes the record) or a retry (which never writes a second
/// one) can't leave it out of sync. [payments] must be every payment under the
/// loan's schedule, INCLUDING payments under installments a re-plan has since
/// retired. Mirrors Web's `principalPrepaidFor` (`lib/engines/loan-outstanding.ts`).
double principalPrepaidFor(Iterable<InstallmentPayment> payments) {
  var total = 0.0;
  for (final p in payments) {
    if (p.deletedAt != null ||
        p.allocationType != PaymentAllocationType.principalPrepayment) {
      continue;
    }
    total += p.prepaymentPrincipalAmount ?? p.amount;
  }
  return total;
}

/// Principal paid off through installments — a fully-paid installment counts
/// its whole principal share, a partially-paid one the prorated fraction.
/// Same formula as `LoanRepository.editLoanTerms` / Web's `principalPaidFor`.
double principalPaidViaInstallments(Iterable<Installment> installments) {
  var total = 0.0;
  for (final i in installments) {
    if (i.amountPaid <= 0) continue;
    final principalShare = i.principalPortion ?? i.amountDue;
    total += i.amountPaid >= i.amountDue
        ? principalShare
        : principalShare * (i.amountPaid / i.amountDue);
  }
  return total;
}

/// Outstanding principal including extra-principal payments — the canonical
/// figure for display, re-plans and Net Worth. Mirrors Web's
/// `outstandingPrincipalAfterPrepaymentsFor`.
double outstandingPrincipalAfterPrepayments({
  required double loanAmount,
  required Iterable<Installment> installments,
  required double principalPrepaid,
}) =>
    (loanAmount - principalPaidViaInstallments(installments) - principalPrepaid)
        .clamp(0, loanAmount)
        .toDouble();
