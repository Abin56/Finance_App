import '../../interest/interest_calculator.dart';
import '../../interest/interest_period.dart';
import 'prepayment_reamortization_policy.dart';
import 'schedule_type.dart';

/// Result of [DisbursementReamortizationPolicy.solve] — either a definite
/// answer or an explicit refusal to guess. Never a silent default.
sealed class DisbursementReamortizationOutcome {
  const DisbursementReamortizationOutcome();
}

/// The remaining schedule keeps [remainingInstallmentCount] installments
/// (unchanged — this is what distinguishes [HoldTenurePolicy] from
/// [ReduceTenurePolicy]) at the recalculated [installmentAmount] each (last
/// one absorbing rounding, same as every other schedule generation in this
/// app).
class DisbursementReamortizationSolved
    extends DisbursementReamortizationOutcome {
  const DisbursementReamortizationSolved({
    required this.remainingInstallmentCount,
    required this.installmentAmount,
  });

  final int remainingInstallmentCount;
  final double installmentAmount;
}

/// The solve could not be safely determined — caller must not attempt
/// automatic regeneration and must surface [reason] to the user with a link
/// to the manual "Edit Loan Terms" fallback. The disbursement itself is
/// still recorded; only the automatic reshape is skipped.
class DisbursementReamortizationUnsolvable
    extends DisbursementReamortizationOutcome {
  const DisbursementReamortizationUnsolvable(this.reason);

  final String reason;
}

/// Solves "how should the schedule reshape after an additional principal
/// disbursement" — a strategy, not a hardcoded algorithm, mirroring
/// [PrepaymentReamortizationPolicy]'s own pluggable shape.
/// [HoldTenurePolicy] is the only v1 implementation; a future
/// `ReduceTenureOnDisbursementPolicy` plugs in here without touching any
/// call site.
abstract class DisbursementReamortizationPolicy {
  DisbursementReamortizationOutcome solve({
    required double outstandingPrincipalAfter,
    required ReamortizationInterestConfig? interest,
    required int remainingInstallmentCount,
    required ScheduleType frequency,
  });
}

/// v1 default: keep the remaining installment COUNT constant (the opposite
/// fixed point from [ReduceTenurePolicy], which holds the amount constant
/// and solves for count) — recalculate the required installment amount for
/// the new, larger outstanding principal over the same number of remaining
/// installments. Never silently applied when the solve doesn't converge —
/// see [DisbursementReamortizationUnsolvable].
class HoldTenurePolicy implements DisbursementReamortizationPolicy {
  const HoldTenurePolicy();

  @override
  DisbursementReamortizationOutcome solve({
    required double outstandingPrincipalAfter,
    required ReamortizationInterestConfig? interest,
    required int remainingInstallmentCount,
    required ScheduleType frequency,
  }) {
    if (outstandingPrincipalAfter <= 0) {
      return const DisbursementReamortizationUnsolvable(
        'Nothing outstanding to re-amortize',
      );
    }
    if (remainingInstallmentCount < 1) {
      return const DisbursementReamortizationUnsolvable(
        'No remaining installments to hold constant',
      );
    }
    if (interest != null && interest.ratePercent < 0) {
      return const DisbursementReamortizationUnsolvable(
        'Interest rate is invalid',
      );
    }

    final installmentsPerYear = _installmentsPerYearFor(frequency);

    final double installmentAmount;
    try {
      if (interest == null || interest.ratePercent == 0) {
        installmentAmount = _round2(
          outstandingPrincipalAfter / remainingInstallmentCount,
        );
      } else {
        final breakdown = InterestCalculator.calculate(
          principal: outstandingPrincipalAfter,
          type: interest.type,
          ratePercent: interest.ratePercent,
          period: interest.period,
          installmentCount: remainingInstallmentCount,
          installmentFrequency: InterestPeriod.monthly,
          installmentsPerYear: installmentsPerYear,
        );
        installmentAmount = breakdown.periods.first.paymentAmount;
      }
    } catch (_) {
      return const DisbursementReamortizationUnsolvable(
        'Interest configuration could not be evaluated',
      );
    }

    if (installmentAmount.isNaN || installmentAmount.isInfinite) {
      return const DisbursementReamortizationUnsolvable(
        'Recalculated installment amount is not a finite number',
      );
    }
    if (installmentAmount <= 0) {
      return const DisbursementReamortizationUnsolvable(
        'Recalculated installment amount must be greater than 0',
      );
    }

    return DisbursementReamortizationSolved(
      remainingInstallmentCount: remainingInstallmentCount,
      installmentAmount: installmentAmount,
    );
  }

  double _round2(double v) => (v * 100).round() / 100;

  int _installmentsPerYearFor(ScheduleType scheduleType) {
    switch (scheduleType) {
      case ScheduleType.weekly:
        return 52;
      case ScheduleType.monthly:
      case ScheduleType.oneTime:
      case ScheduleType.custom:
        return 12;
    }
  }
}
