import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_status.dart';

/// The single reusable set of financial numbers for one loan — computed
/// purely from its [Installment]s (whose own `amountPaid` is kept in sync by
/// `InstallmentRepository.applyPayment` off the `InstallmentPayment`
/// subcollection, the real source of truth). No screen should recompute any
/// of these from installments directly; watch `loanFinancialSummaryProvider`
/// instead so every consumer (loan detail, loan list, dashboard, cash flow,
/// reports, people, EMI schedule) agrees on the same numbers.
///
/// Pure — no I/O, no Riverpod dependency, mirrors `PersonCycleSummary.from`'s
/// shape (a value object built by a static factory over already-loaded data).
class LoanFinancialSummary {
  const LoanFinancialSummary({
    required this.originalPrincipal,
    required this.totalScheduledInterest,
    required this.totalScheduledPayable,
    required this.totalPaid,
    required this.outstanding,
    required this.principalPaid,
    required this.interestPaid,
    required this.principalRemaining,
    required this.interestRemaining,
    required this.paidInstallments,
    required this.partialInstallments,
    required this.remainingInstallments,
    required this.nextInstallment,
    required this.overdueInstallments,
    required this.overdueAmount,
    required this.progress,
  });

  /// The original loan amount, before any interest.
  final double originalPrincipal;

  /// Sum of every installment's `interestPortion` — zero for a loan with no
  /// interest (installments never carry a `principalPortion`/`interestPortion`
  /// split in that case).
  final double totalScheduledInterest;

  /// Total amount scheduled to be paid according to the current valid
  /// schedule — sum of every non-deleted installment's `amountDue`.
  final double totalScheduledPayable;

  /// Sum of valid, non-deleted actual installment payments — each
  /// installment's cached `amountPaid`.
  final double totalPaid;

  /// `totalScheduledPayable - totalPaid`, clamped to zero — mirrors
  /// `Installment.remainingAmount`'s own clamping so this can never go
  /// negative from an over-applied payment.
  final double outstanding;

  /// Sum of principal actually paid down so far. For a no-interest loan this
  /// equals [totalPaid] (the whole `amountDue` is principal). For an
  /// interest-bearing loan, each installment's payment is credited to
  /// principal only once that installment's own `interestPortion` is fully
  /// covered — the standard "interest first, then principal" convention
  /// within a single installment.
  final double principalPaid;

  /// Sum of interest actually paid down so far (complementary to
  /// [principalPaid] — `principalPaid + interestPaid == totalPaid`).
  final double interestPaid;

  /// `originalPrincipal - principalPaid`, clamped to zero.
  final double principalRemaining;

  /// `totalScheduledInterest - interestPaid`, clamped to zero.
  final double interestRemaining;

  /// Installments whose `remainingAmount` is zero (fully paid, per
  /// `Installment.status == InstallmentStatus.paid`).
  final int paidInstallments;

  /// Installments with `0 < amountPaid < amountDue` (per
  /// `InstallmentStatus.partiallyPaid`) — a subset of "remaining", counted
  /// separately since a partially-paid installment still owes money but
  /// isn't fully unpaid either.
  final int remainingInstallments;

  /// installments with `amountPaid > 0 && amountPaid < amountDue` — same set
  /// [remainingInstallments] pulls its partial count from, exposed directly
  /// since callers often want this without also wanting the "untouched
  /// remaining" count.
  final int partialInstallments;

  /// The earliest unpaid, non-skipped installment (by `sequenceNumber`) —
  /// `null` once every installment is settled. Same definition
  /// `loanNextUpcomingInstallmentProvider` already uses.
  final Installment? nextInstallment;

  /// Count of installments currently `InstallmentStatus.overdue` — the
  /// existing status/date rule, not a new one (an installment already
  /// partially paid, skipped, or fully paid is never "overdue" per
  /// `Installment.status`).
  final int overdueInstallments;

  /// Sum of `remainingAmount` across overdue installments only.
  final double overdueAmount;

  /// `totalPaid / totalScheduledPayable` in `[0.0, 1.0]` — `1.0` when there's
  /// nothing scheduled to pay (e.g. a defensive edge case, never actually
  /// reachable since every loan has at least one installment).
  final double progress;

  /// Builds the summary from every one of a loan's non-deleted installments
  /// (typically `installmentsStreamProvider(loan.scheduleId)`'s value) plus
  /// the loan's own original principal. Handles zero-interest loans (no
  /// installment carries a `principalPortion`/`interestPortion`, so
  /// [totalScheduledInterest] is 0 and every paid rupee counts as principal),
  /// partial/early/overdue payments, skipped installments (excluded from
  /// "remaining"/"next" but still contribute their `amountPaid` to
  /// [totalPaid]), and lump-sum settlement (already reflected in each
  /// installment's `amountPaid` by the time this runs — no separate
  /// handling needed here).
  static LoanFinancialSummary from({
    required List<Installment> installments,
    required double originalPrincipal,
  }) {
    final sorted = [...installments]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    var totalScheduledInterest = 0.0;
    var totalScheduledPayable = 0.0;
    var totalPaid = 0.0;
    var principalPaid = 0.0;
    var interestPaid = 0.0;
    var paidInstallments = 0;
    var partialInstallments = 0;
    var overdueInstallments = 0;
    var overdueAmount = 0.0;

    for (final installment in sorted) {
      final interestPortion = installment.interestPortion ?? 0;
      totalScheduledInterest += interestPortion;
      totalScheduledPayable += installment.amountDue;
      totalPaid += installment.amountPaid;

      // Interest-first-then-principal within a single installment — the
      // standard repayment convention, matching the prior per-screen logic
      // this replaces (previously duplicated in loan_detail_screen.dart).
      final paidTowardInterest = installment.amountPaid.clamp(0, interestPortion);
      interestPaid += paidTowardInterest;
      principalPaid += installment.amountPaid - paidTowardInterest;

      switch (installment.status) {
        case InstallmentStatus.paid:
          paidInstallments++;
        case InstallmentStatus.partiallyPaid:
          partialInstallments++;
        case InstallmentStatus.overdue:
          overdueInstallments++;
          overdueAmount += installment.remainingAmount;
        case InstallmentStatus.skipped:
        case InstallmentStatus.upcoming:
          break;
      }
    }

    final remainingInstallments = sorted.where((i) => i.remainingAmount > 0).length;
    final nextInstallment =
        sorted.where((i) => i.status != InstallmentStatus.paid && !i.isSkipped).firstOrNull;

    final outstanding = (totalScheduledPayable - totalPaid).clamp(0, totalScheduledPayable).toDouble();
    final principalRemaining = (originalPrincipal - principalPaid).clamp(0, originalPrincipal).toDouble();
    final interestRemaining =
        (totalScheduledInterest - interestPaid).clamp(0, totalScheduledInterest).toDouble();
    final progress = totalScheduledPayable <= 0 ? 1.0 : (totalPaid / totalScheduledPayable).clamp(0.0, 1.0);

    return LoanFinancialSummary(
      originalPrincipal: originalPrincipal,
      totalScheduledInterest: totalScheduledInterest,
      totalScheduledPayable: totalScheduledPayable,
      totalPaid: totalPaid,
      outstanding: outstanding,
      principalPaid: principalPaid,
      interestPaid: interestPaid,
      principalRemaining: principalRemaining,
      interestRemaining: interestRemaining,
      paidInstallments: paidInstallments,
      partialInstallments: partialInstallments,
      remainingInstallments: remainingInstallments,
      nextInstallment: nextInstallment,
      overdueInstallments: overdueInstallments,
      overdueAmount: overdueAmount,
      progress: progress,
    );
  }
}
