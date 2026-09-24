import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';
import 'package:finance_app/core/payment_schedule/domain/prepayment_reamortization_policy.dart';
import 'package:finance_app/core/payment_schedule/domain/schedule_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ReduceTenurePolicy();

  group('ReduceTenurePolicy.solve — solved cases', () {
    test('reducing-balance: solves to fewer installments at or under the target', () {
      final outcome = policy.solve(
        outstandingPrincipalAfter: 6053.81,
        interest: const ReamortizationInterestConfig(
          type: InterestType.reducingBalance,
          ratePercent: 12,
          period: InterestPeriod.yearly,
        ),
        targetInstallmentAmount: 1066.19,
        frequency: ScheduleType.monthly,
      );

      expect(outcome, isA<PrepaymentReamortizationSolved>());
      final solved = outcome as PrepaymentReamortizationSolved;
      expect(solved.remainingInstallmentCount, lessThan(11));
      expect(solved.installmentAmount, lessThanOrEqualTo(1066.19));
    });

    test('zero-interest: solves via direct division', () {
      final outcome = policy.solve(
        outstandingPrincipalAfter: 5000,
        interest: null,
        targetInstallmentAmount: 1000,
        frequency: ScheduleType.monthly,
      );

      expect(outcome, isA<PrepaymentReamortizationSolved>());
      final solved = outcome as PrepaymentReamortizationSolved;
      expect(solved.remainingInstallmentCount, 5);
      expect(solved.installmentAmount, 1000);
    });

    test('when outstanding already fits in 1 installment at/under target', () {
      final outcome = policy.solve(
        outstandingPrincipalAfter: 500,
        interest: null,
        targetInstallmentAmount: 1000,
        frequency: ScheduleType.monthly,
      );
      expect(outcome, isA<PrepaymentReamortizationSolved>());
      expect(
        (outcome as PrepaymentReamortizationSolved).remainingInstallmentCount,
        1,
      );
    });
  });

  group(
    'ReduceTenurePolicy.solve — unsolvable cases (never silently guesses)',
    () {
      test('outstandingPrincipalAfter <= 0 is unsolvable', () {
        final outcome = policy.solve(
          outstandingPrincipalAfter: 0,
          interest: null,
          targetInstallmentAmount: 1000,
          frequency: ScheduleType.monthly,
        );
        expect(outcome, isA<PrepaymentReamortizationUnsolvable>());
      });

      test('negative outstandingPrincipalAfter is unsolvable', () {
        final outcome = policy.solve(
          outstandingPrincipalAfter: -100,
          interest: null,
          targetInstallmentAmount: 1000,
          frequency: ScheduleType.monthly,
        );
        expect(outcome, isA<PrepaymentReamortizationUnsolvable>());
      });

      test('targetInstallmentAmount <= 0 is unsolvable', () {
        final outcome = policy.solve(
          outstandingPrincipalAfter: 5000,
          interest: null,
          targetInstallmentAmount: 0,
          frequency: ScheduleType.monthly,
        );
        expect(outcome, isA<PrepaymentReamortizationUnsolvable>());
      });

      test('negative interest rate is unsolvable', () {
        final outcome = policy.solve(
          outstandingPrincipalAfter: 5000,
          interest: const ReamortizationInterestConfig(
            type: InterestType.reducingBalance,
            ratePercent: -5,
            period: InterestPeriod.yearly,
          ),
          targetInstallmentAmount: 1000,
          frequency: ScheduleType.monthly,
        );
        expect(outcome, isA<PrepaymentReamortizationUnsolvable>());
      });

      test(
        'a target amount too small to ever cover the interest on a large '
        'principal is unsolvable (never returns a guessed count)',
        () {
          // At 24%/year reducing balance, the first period's interest alone
          // on a huge principal exceeds a tiny target every period, so no
          // installment count within the policy's search bound can ever
          // bring the payment at or below target.
          final outcome = policy.solve(
            outstandingPrincipalAfter: 10000000,
            interest: const ReamortizationInterestConfig(
              type: InterestType.reducingBalance,
              ratePercent: 24,
              period: InterestPeriod.yearly,
            ),
            targetInstallmentAmount: 1,
            frequency: ScheduleType.monthly,
          );
          expect(outcome, isA<PrepaymentReamortizationUnsolvable>());
        },
      );
    },
  );
}
