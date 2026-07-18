import 'interest_breakdown.dart';
import 'interest_period.dart';
import 'interest_type.dart';

/// Pure amortization math — no Firestore/Riverpod dependency. Computes how
/// a [principal] is repaid over [installmentCount] periods at [ratePercent]%
/// per [period], for either [InterestType.flat] or
/// [InterestType.reducingBalance] interest. Reusable by any future
/// lending/borrowing feature; the caller is responsible for turning the
/// result into persisted records (see `Installment.principalPortion`).
abstract class InterestCalculator {
  InterestCalculator._();

  /// [installmentCount] must be >= 1 (1 means a one-time repayment — both
  /// formulas below degrade correctly to a single period, so one-time and
  /// installment repayment share identical math with no special-casing).
  ///
  /// [installmentFrequency] normalizes the rate for a monthly- or yearly-
  /// cadence schedule. For any other cadence (e.g. a weekly repayment
  /// schedule), pass [installmentsPerYear] instead — e.g. 52 for weekly —
  /// so the rate is converted to a true per-installment rate rather than
  /// being forced through the nearest of monthly/yearly (which overstates
  /// or understates interest for any cadence that isn't actually monthly
  /// or yearly). When [installmentsPerYear] is provided, it takes
  /// precedence over [installmentFrequency].
  static InterestBreakdown calculate({
    required double principal,
    required InterestType type,
    required double ratePercent,
    required InterestPeriod period,
    required int installmentCount,
    required InterestPeriod installmentFrequency,
    int? installmentsPerYear,
  }) {
    if (installmentCount < 1) {
      throw ArgumentError.value(installmentCount, 'installmentCount', 'must be at least 1');
    }
    if (ratePercent < 0) {
      throw ArgumentError.value(ratePercent, 'ratePercent', 'cannot be negative');
    }
    if (ratePercent == 0) {
      return _zeroInterest(principal, installmentCount);
    }

    final periodicRate = installmentCount == 1
        ? ratePercent
        : _periodicRate(ratePercent, period, installmentFrequency, installmentsPerYear: installmentsPerYear);
    return type == InterestType.flat
        ? _flat(principal, periodicRate, installmentCount)
        : _reducingBalance(principal, periodicRate, installmentCount);
  }

  /// Converts an annual/monthly nominal [ratePercent] into the rate that
  /// applies once per installment. E.g. a 12%/yearly rate on monthly
  /// installments becomes 1%/month; a 2%/monthly rate on yearly
  /// installments becomes 24%/year; a 12%/yearly rate on weekly
  /// installments ([installmentsPerYear] = 52) becomes ~0.23%/week. Not
  /// used for a single-period (one-time) repayment — see [calculate].
  static double _periodicRate(
    double ratePercent,
    InterestPeriod quotedPeriod,
    InterestPeriod installmentFrequency, {
    int? installmentsPerYear,
  }) {
    final annualRate = quotedPeriod == InterestPeriod.yearly ? ratePercent : ratePercent * 12;
    if (installmentsPerYear != null) return annualRate / installmentsPerYear;
    return installmentFrequency == InterestPeriod.yearly ? annualRate : annualRate / 12;
  }

  static InterestBreakdown _zeroInterest(double principal, int installmentCount) {
    final principalShares = _evenSplit(principal, installmentCount);
    final periods = <InterestPeriodBreakdown>[];
    var remaining = principal;
    for (var i = 0; i < installmentCount; i++) {
      remaining = (remaining - principalShares[i]).clamp(0, principal).toDouble();
      periods.add(InterestPeriodBreakdown(
        periodNumber: i + 1,
        paymentAmount: principalShares[i],
        principalPortion: principalShares[i],
        interestPortion: 0,
        remainingPrincipal: remaining,
      ));
    }
    return InterestBreakdown(principal: principal, totalInterest: 0, periods: periods);
  }

  /// Flat/simple interest: total interest = principal * periodicRate/100 *
  /// installmentCount (rate applied to the ORIGINAL principal every period,
  /// never to a reducing balance). Total payable is split evenly across
  /// installments (equal principal share + equal interest share per
  /// period), with the last installment absorbing any rounding remainder.
  static InterestBreakdown _flat(double principal, double periodicRate, int installmentCount) {
    final totalInterest = _round2(principal * (periodicRate / 100) * installmentCount);
    final principalShares = _evenSplit(principal, installmentCount);
    final interestShares = _evenSplit(totalInterest, installmentCount);

    final periods = <InterestPeriodBreakdown>[];
    var remainingPrincipal = principal;
    for (var i = 0; i < installmentCount; i++) {
      remainingPrincipal = (remainingPrincipal - principalShares[i]).clamp(0, principal).toDouble();
      periods.add(InterestPeriodBreakdown(
        periodNumber: i + 1,
        paymentAmount: _round2(principalShares[i] + interestShares[i]),
        principalPortion: principalShares[i],
        interestPortion: interestShares[i],
        remainingPrincipal: remainingPrincipal,
      ));
    }
    return InterestBreakdown(principal: principal, totalInterest: totalInterest, periods: periods);
  }

  /// Reducing balance / amortized interest: standard EMI annuity formula.
  /// Fixed periodic payment, interest recomputed each period on the
  /// OUTSTANDING principal, principal portion = payment - interest portion.
  /// Last installment absorbs rounding remainder and is clamped so
  /// remainingPrincipal never goes negative (guards against float drift
  /// over many periods).
  static InterestBreakdown _reducingBalance(double principal, double periodicRate, int installmentCount) {
    final r = periodicRate / 100;
    final emi = principal * r * _pow(1 + r, installmentCount) / (_pow(1 + r, installmentCount) - 1);

    final periods = <InterestPeriodBreakdown>[];
    var outstanding = principal;
    var totalInterest = 0.0;
    for (var i = 0; i < installmentCount; i++) {
      final isLast = i == installmentCount - 1;
      final interestPortion = _round2(outstanding * r);
      var principalPortion = isLast ? outstanding : _round2(emi - interestPortion);
      if (principalPortion > outstanding) principalPortion = outstanding;
      outstanding = (outstanding - principalPortion).clamp(0, principal).toDouble();
      totalInterest += interestPortion;
      periods.add(InterestPeriodBreakdown(
        periodNumber: i + 1,
        paymentAmount: _round2(principalPortion + interestPortion),
        principalPortion: principalPortion,
        interestPortion: interestPortion,
        remainingPrincipal: outstanding,
      ));
    }
    return InterestBreakdown(principal: principal, totalInterest: _round2(totalInterest), periods: periods);
  }

  static List<double> _evenSplit(double total, int count) {
    final share = _round2(total / count);
    final shares = List.filled(count, share);
    final remainder = _round2(total - share * count);
    shares[count - 1] = _round2(shares[count - 1] + remainder);
    return shares;
  }

  static double _pow(double base, int exp) {
    var result = 1.0;
    for (var i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  static double _round2(double v) => (v * 100).round() / 100;
}
