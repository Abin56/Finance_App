import '../../interest/interest_calculator.dart';
import '../../interest/interest_period.dart';
import '../../interest/interest_type.dart';
import 'schedule_type.dart';

/// Optional interest terms a policy solves against — a minimal, engine-only
/// shape (not `LoanInterest`, which `lib/core` must not depend on).
class ReamortizationInterestConfig {
  const ReamortizationInterestConfig({
    required this.type,
    required this.ratePercent,
    required this.period,
  });

  final InterestType type;
  final double ratePercent;
  final InterestPeriod period;
}

/// Result of [PrepaymentReamortizationPolicy.solve] — either a definite
/// answer or an explicit refusal to guess. Never a silent default.
sealed class PrepaymentReamortizationOutcome {
  const PrepaymentReamortizationOutcome();
}

/// The new tail should have [remainingInstallmentCount] installments at
/// [installmentAmount] each (last one absorbing rounding, same as every
/// other schedule generation in this app).
class PrepaymentReamortizationSolved extends PrepaymentReamortizationOutcome {
  const PrepaymentReamortizationSolved({
    required this.remainingInstallmentCount,
    required this.installmentAmount,
  });

  final int remainingInstallmentCount;
  final double installmentAmount;
}

/// The solve could not be safely determined — caller must not attempt
/// `editLoanTerms`/regeneration and must surface [reason] to the user with a
/// link to the manual "Edit Loan Terms" fallback. The payment itself is
/// still recorded; only the automatic reshape is skipped.
class PrepaymentReamortizationUnsolvable
    extends PrepaymentReamortizationOutcome {
  const PrepaymentReamortizationUnsolvable(this.reason);

  final String reason;
}

/// Solves "how should the schedule reshape after a principal prepayment"
/// (or an additional disbursement, which is the same solve with a positive
/// principal delta). A strategy, not a hardcoded algorithm — `ReduceTenurePolicy`
/// is the only v1 implementation; a future `ReduceEmiAmountPolicy` plugs in
/// here without touching any call site.
abstract class PrepaymentReamortizationPolicy {
  PrepaymentReamortizationOutcome solve({
    required double outstandingPrincipalAfter,
    required ReamortizationInterestConfig? interest,
    required double targetInstallmentAmount,
    required ScheduleType frequency,
  });
}

/// v1 default: keep the installment amount constant (approximately — see
/// [targetInstallmentAmount]), shorten the number of remaining installments.
/// Never silently applied when the solve doesn't converge — see
/// [PrepaymentReamortizationUnsolvable].
class ReduceTenurePolicy implements PrepaymentReamortizationPolicy {
  const ReduceTenurePolicy();

  /// Upper bound on how many installments this solve will ever consider —
  /// a sane guard against runaway iteration (100 years of monthly
  /// installments), not a real product limit. Hitting it means the target
  /// amount is too small to ever pay off the outstanding principal at this
  /// interest rate (or the rate is malformed), which is exactly the
  /// "cannot be safely determined" case this policy must refuse to guess.
  static const int _maxIterations = 1200;

  @override
  PrepaymentReamortizationOutcome solve({
    required double outstandingPrincipalAfter,
    required ReamortizationInterestConfig? interest,
    required double targetInstallmentAmount,
    required ScheduleType frequency,
  }) {
    if (outstandingPrincipalAfter <= 0) {
      return const PrepaymentReamortizationUnsolvable(
        'Nothing outstanding to re-amortize',
      );
    }
    if (targetInstallmentAmount <= 0) {
      return const PrepaymentReamortizationUnsolvable(
        'No target installment amount to hold constant',
      );
    }
    if (interest != null && interest.ratePercent < 0) {
      return const PrepaymentReamortizationUnsolvable(
        'Interest rate is invalid',
      );
    }

    final installmentsPerYear = _installmentsPerYearFor(frequency);

    for (var count = 1; count <= _maxIterations; count++) {
      final double firstInstallmentAmount;
      try {
        if (interest == null || interest.ratePercent == 0) {
          firstInstallmentAmount = _round2(outstandingPrincipalAfter / count);
        } else {
          final breakdown = InterestCalculator.calculate(
            principal: outstandingPrincipalAfter,
            type: interest.type,
            ratePercent: interest.ratePercent,
            period: interest.period,
            installmentCount: count,
            installmentFrequency: InterestPeriod.monthly,
            installmentsPerYear: installmentsPerYear,
          );
          firstInstallmentAmount = breakdown.periods.first.paymentAmount;
        }
      } catch (_) {
        return const PrepaymentReamortizationUnsolvable(
          'Interest configuration could not be evaluated',
        );
      }

      if (firstInstallmentAmount <= targetInstallmentAmount) {
        return PrepaymentReamortizationSolved(
          remainingInstallmentCount: count,
          installmentAmount: firstInstallmentAmount,
        );
      }
    }

    return const PrepaymentReamortizationUnsolvable(
      'Could not find a tenure that keeps the installment amount at or '
      'below its current value within a reasonable number of payments',
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
