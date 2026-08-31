// Validation harness — imports the REAL Flutter engine source directly and
// prints JSON so it can be diffed against the TypeScript port's output for
// identical inputs. Run from inside the Finance_App repo so relative
// imports resolve.
import 'dart:convert';
import 'package:finance_app/core/interest/interest_breakdown.dart';
import 'package:finance_app/core/interest/interest_calculator.dart';
import 'package:finance_app/core/interest/interest_period.dart';
import 'package:finance_app/core/interest/interest_type.dart';

Map<String, dynamic> breakdownToJson(InterestBreakdown b) => {
      'principal': b.principal,
      'totalInterest': b.totalInterest,
      'totalPayable': b.totalPayable,
      'periods': b.periods
          .map((p) => {
                'periodNumber': p.periodNumber,
                'paymentAmount': p.paymentAmount,
                'principalPortion': p.principalPortion,
                'interestPortion': p.interestPortion,
                'remainingPrincipal': p.remainingPrincipal,
              })
          .toList(),
    };

void main() {
  final cases = <String, InterestBreakdown>{
    'reducingBalance_monthly_12pct_12mo': InterestCalculator.calculate(
      principal: 120000,
      type: InterestType.reducingBalance,
      ratePercent: 12,
      period: InterestPeriod.yearly,
      installmentCount: 12,
      installmentFrequency: InterestPeriod.monthly,
    ),
    'flat_yearly_10pct_24mo': InterestCalculator.calculate(
      principal: 50000,
      type: InterestType.flat,
      ratePercent: 10,
      period: InterestPeriod.yearly,
      installmentCount: 24,
      installmentFrequency: InterestPeriod.monthly,
    ),
    'zeroInterest_6mo': InterestCalculator.calculate(
      principal: 30000,
      type: InterestType.flat,
      ratePercent: 0,
      period: InterestPeriod.monthly,
      installmentCount: 6,
      installmentFrequency: InterestPeriod.monthly,
    ),
    'oneTime_reducingBalance': InterestCalculator.calculate(
      principal: 10000,
      type: InterestType.reducingBalance,
      ratePercent: 5,
      period: InterestPeriod.monthly,
      installmentCount: 1,
      installmentFrequency: InterestPeriod.monthly,
    ),
    'weekly_installmentsPerYear': InterestCalculator.calculate(
      principal: 20000,
      type: InterestType.reducingBalance,
      ratePercent: 12,
      period: InterestPeriod.yearly,
      installmentCount: 10,
      installmentFrequency: InterestPeriod.monthly,
      installmentsPerYear: 52,
    ),
    'reducingBalance_odd_principal_7mo': InterestCalculator.calculate(
      principal: 133337.77,
      type: InterestType.reducingBalance,
      ratePercent: 14.5,
      period: InterestPeriod.yearly,
      installmentCount: 7,
      installmentFrequency: InterestPeriod.monthly,
    ),
  };

  final out = cases.map((k, v) => MapEntry(k, breakdownToJson(v)));
  print(const JsonEncoder.withIndent('  ').convert(out));
}
