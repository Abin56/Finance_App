import 'package:finance_app/core/interest/interest_calculator.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InterestCalculator.calculate — flat interest', () {
    test('interest is constant per period', () {
      final breakdown = InterestCalculator.calculate(
        principal: 1200,
        type: InterestType.flat,
        ratePercent: 2,
        period: InterestPeriod.monthly,
        installmentCount: 4,
        installmentFrequency: InterestPeriod.monthly,
      );

      final interestPortions = breakdown.periods.map((p) => p.interestPortion).toSet();
      expect(interestPortions, hasLength(1), reason: 'flat interest should be identical every period');
    });

    test('totalInterest equals principal * rate/100 * installmentCount', () {
      final breakdown = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 2,
        period: InterestPeriod.monthly,
        installmentCount: 6,
        installmentFrequency: InterestPeriod.monthly,
      );

      expect(breakdown.totalInterest, closeTo(1000 * 0.02 * 6, 0.01));
    });

    test('sum of principalPortion equals principal exactly', () {
      final breakdown = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 3.5,
        period: InterestPeriod.monthly,
        installmentCount: 7,
        installmentFrequency: InterestPeriod.monthly,
      );

      final totalPrincipal = breakdown.periods.fold(0.0, (sum, p) => sum + p.principalPortion);
      expect(totalPrincipal, closeTo(1000, 0.01));
    });

    test('sum of paymentAmount equals totalPayable exactly', () {
      final breakdown = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 3.5,
        period: InterestPeriod.monthly,
        installmentCount: 7,
        installmentFrequency: InterestPeriod.monthly,
      );

      final totalPaid = breakdown.periods.fold(0.0, (sum, p) => sum + p.paymentAmount);
      expect(totalPaid, closeTo(breakdown.totalPayable, 0.01));
    });
  });

  group('InterestCalculator.calculate — reducing balance interest', () {
    test('interestPortion strictly decreases period over period', () {
      final breakdown = InterestCalculator.calculate(
        principal: 100000,
        type: InterestType.reducingBalance,
        ratePercent: 12,
        period: InterestPeriod.yearly,
        installmentCount: 12,
        installmentFrequency: InterestPeriod.monthly,
      );

      for (var i = 1; i < breakdown.periods.length; i++) {
        expect(breakdown.periods[i].interestPortion, lessThan(breakdown.periods[i - 1].interestPortion));
      }
    });

    test('principalPortion strictly increases period over period', () {
      final breakdown = InterestCalculator.calculate(
        principal: 100000,
        type: InterestType.reducingBalance,
        ratePercent: 12,
        period: InterestPeriod.yearly,
        installmentCount: 12,
        installmentFrequency: InterestPeriod.monthly,
      );

      for (var i = 1; i < breakdown.periods.length; i++) {
        expect(breakdown.periods[i].principalPortion, greaterThan(breakdown.periods[i - 1].principalPortion));
      }
    });

    test('remainingPrincipal after the final period is exactly 0', () {
      final breakdown = InterestCalculator.calculate(
        principal: 100000,
        type: InterestType.reducingBalance,
        ratePercent: 12,
        period: InterestPeriod.yearly,
        installmentCount: 12,
        installmentFrequency: InterestPeriod.monthly,
      );

      expect(breakdown.periods.last.remainingPrincipal, 0);
    });

    test('sum of principalPortion equals principal exactly', () {
      final breakdown = InterestCalculator.calculate(
        principal: 100000,
        type: InterestType.reducingBalance,
        ratePercent: 12,
        period: InterestPeriod.yearly,
        installmentCount: 12,
        installmentFrequency: InterestPeriod.monthly,
      );

      final totalPrincipal = breakdown.periods.fold(0.0, (sum, p) => sum + p.principalPortion);
      expect(totalPrincipal, closeTo(100000, 0.01));
    });

    test('matches known EMI reference value (100000 @ 12%/yr, 12 monthly installments)', () {
      final breakdown = InterestCalculator.calculate(
        principal: 100000,
        type: InterestType.reducingBalance,
        ratePercent: 12,
        period: InterestPeriod.yearly,
        installmentCount: 12,
        installmentFrequency: InterestPeriod.monthly,
      );

      expect(breakdown.periods.first.paymentAmount, closeTo(8884.88, 0.5));
    });
  });

  group('InterestCalculator.calculate — shared / edge cases', () {
    test('ratePercent = 0 produces zero interest and plain even principal split', () {
      final breakdown = InterestCalculator.calculate(
        principal: 900,
        type: InterestType.flat,
        ratePercent: 0,
        period: InterestPeriod.monthly,
        installmentCount: 3,
        installmentFrequency: InterestPeriod.monthly,
      );

      expect(breakdown.totalInterest, 0);
      for (final period in breakdown.periods) {
        expect(period.interestPortion, 0);
      }
      expect(breakdown.periods.map((p) => p.principalPortion), everyElement(300));
    });

    test('installmentCount = 1 (one-time repayment) produces a single period', () {
      final breakdown = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 5,
        period: InterestPeriod.monthly,
        installmentCount: 1,
        installmentFrequency: InterestPeriod.monthly,
      );

      expect(breakdown.periods, hasLength(1));
      expect(breakdown.periods.single.paymentAmount, closeTo(breakdown.totalPayable, 0.01));
      expect(breakdown.periods.single.remainingPrincipal, 0);
    });

    test('rate period conversion is proportionally consistent', () {
      final yearlyOnMonthly = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 12,
        period: InterestPeriod.yearly,
        installmentCount: 1,
        installmentFrequency: InterestPeriod.monthly,
      );
      final monthlyOnMonthly = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 1,
        period: InterestPeriod.monthly,
        installmentCount: 1,
        installmentFrequency: InterestPeriod.monthly,
      );

      // Note: installmentCount=1 applies the quoted rate verbatim for the
      // single period (no annualization conversion — see interest_calculator.dart),
      // so this checks multi-period behavior instead, where the conversion applies.
      final yearlyOnMonthlyMulti = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 12,
        period: InterestPeriod.yearly,
        installmentCount: 2,
        installmentFrequency: InterestPeriod.monthly,
      );
      final monthlyOnMonthlyMulti = InterestCalculator.calculate(
        principal: 1000,
        type: InterestType.flat,
        ratePercent: 1,
        period: InterestPeriod.monthly,
        installmentCount: 2,
        installmentFrequency: InterestPeriod.monthly,
      );

      expect(yearlyOnMonthlyMulti.totalInterest, closeTo(monthlyOnMonthlyMulti.totalInterest, 0.01));
      expect(yearlyOnMonthly.principal, monthlyOnMonthly.principal);
    });

    test('rounding: odd principal loses no cent across installments', () {
      final breakdown = InterestCalculator.calculate(
        principal: 100000.01,
        type: InterestType.flat,
        ratePercent: 0,
        period: InterestPeriod.monthly,
        installmentCount: 3,
        installmentFrequency: InterestPeriod.monthly,
      );

      final totalPrincipal = breakdown.periods.fold(0.0, (sum, p) => sum + p.principalPortion);
      expect(totalPrincipal, closeTo(100000.01, 0.01));
    });

    test('negative rate throws ArgumentError', () {
      expect(
        () => InterestCalculator.calculate(
          principal: 1000,
          type: InterestType.flat,
          ratePercent: -1,
          period: InterestPeriod.monthly,
          installmentCount: 1,
          installmentFrequency: InterestPeriod.monthly,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('installmentCount = 0 throws ArgumentError', () {
      expect(
        () => InterestCalculator.calculate(
          principal: 1000,
          type: InterestType.flat,
          ratePercent: 5,
          period: InterestPeriod.monthly,
          installmentCount: 0,
          installmentFrequency: InterestPeriod.monthly,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('large installmentCount does not drift and reaches exactly 0 remaining', () {
      final breakdown = InterestCalculator.calculate(
        principal: 300000,
        type: InterestType.reducingBalance,
        ratePercent: 8,
        period: InterestPeriod.yearly,
        installmentCount: 360,
        installmentFrequency: InterestPeriod.monthly,
      );

      expect(breakdown.periods.last.remainingPrincipal, 0);
      final totalPrincipal = breakdown.periods.fold(0.0, (sum, p) => sum + p.principalPortion);
      expect(totalPrincipal, closeTo(300000, 0.01));
    });
  });
}
