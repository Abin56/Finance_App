import 'package:finance_app/features/insights/domain/insight.dart';
import 'package:finance_app/features/insights/domain/insight_inputs.dart';
import 'package:finance_app/features/insights/domain/insight_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const _zeroInputs = InsightInputs(income: 0, expenses: 0, previousIncome: 0, previousExpenses: 0);

void main() {
  group('netSavingsTrendRule', () {
    test('returns null with no previous-period savings to compare against', () {
      final inputs = InsightInputs(income: 1000, expenses: 500, previousIncome: 0, previousExpenses: 0);
      expect(netSavingsTrendRule(inputs), isNull);
    });

    test('positive severity when this period saved more', () {
      final inputs = InsightInputs(income: 2000, expenses: 500, previousIncome: 1000, previousExpenses: 500);
      final insight = netSavingsTrendRule(inputs);
      expect(insight, isNotNull);
      expect(insight!.severity, InsightSeverity.positive);
      expect(insight.category, InsightCategory.savings);
    });

    test('warning severity when this period saved less', () {
      final inputs = InsightInputs(income: 1000, expenses: 800, previousIncome: 1000, previousExpenses: 200);
      final insight = netSavingsTrendRule(inputs);
      expect(insight, isNotNull);
      expect(insight!.severity, InsightSeverity.warning);
    });

    test('returns null when savings are unchanged', () {
      final inputs = InsightInputs(income: 1000, expenses: 500, previousIncome: 1000, previousExpenses: 500);
      expect(netSavingsTrendRule(inputs), isNull);
    });
  });

  group('topSpendingCategoryRule', () {
    test('returns null with no top category', () {
      expect(topSpendingCategoryRule(_zeroInputs), isNull);
    });

    test('neutral severity with no previous-period amount to compare', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        topCategoryName: 'Groceries',
        topCategoryAmount: 500,
      );
      final insight = topSpendingCategoryRule(inputs);
      expect(insight, isNotNull);
      expect(insight!.severity, InsightSeverity.neutral);
    });

    test('warning severity when spending increased vs previous period', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        topCategoryName: 'Groceries',
        topCategoryAmount: 600,
        previousTopCategoryAmount: 400,
      );
      final insight = topSpendingCategoryRule(inputs);
      expect(insight, isNotNull);
      expect(insight!.severity, InsightSeverity.warning);
      expect(insight.message, contains('increased'));
    });

    test('positive severity when spending decreased vs previous period', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        topCategoryName: 'Groceries',
        topCategoryAmount: 300,
        previousTopCategoryAmount: 400,
      );
      final insight = topSpendingCategoryRule(inputs);
      expect(insight, isNotNull);
      expect(insight!.severity, InsightSeverity.positive);
      expect(insight.message, contains('decreased'));
    });
  });

  group('creditUtilizationRule', () {
    test('returns null with no utilization figure', () {
      expect(creditUtilizationRule(_zeroInputs), isNull);
    });

    test('warns at or above 75% utilization regardless of trend', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        creditUtilization: 0.8,
      );
      final insight = creditUtilizationRule(inputs);
      expect(insight, isNotNull);
      expect(insight!.severity, InsightSeverity.warning);
    });

    test('positive when utilization decreased below the warning threshold', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        creditUtilization: 0.3,
        previousCreditUtilization: 0.5,
      );
      final insight = creditUtilizationRule(inputs);
      expect(insight, isNotNull);
      expect(insight!.severity, InsightSeverity.positive);
    });

    test('returns null for a negligible change', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        creditUtilization: 0.31,
        previousCreditUtilization: 0.30,
      );
      expect(creditUtilizationRule(inputs), isNull);
    });
  });

  group('upcomingDueRule', () {
    test('returns null when due total is small relative to income', () {
      final inputs = InsightInputs(
        income: 10000,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        upcomingDueTotal: 100,
      );
      expect(upcomingDueRule(inputs), isNull);
    });

    test('surfaces when due total is at least half of income', () {
      final inputs = InsightInputs(
        income: 10000,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        upcomingDueTotal: 6000,
      );
      expect(upcomingDueRule(inputs), isNotNull);
    });
  });

  group('savingsRateIndicatorRule', () {
    test('returns null with zero income (undefined rate)', () {
      expect(savingsRateIndicatorRule(_zeroInputs), isNull);
    });

    test('Good at or above 20% savings rate', () {
      final inputs = InsightInputs(income: 1000, expenses: 700, previousIncome: 0, previousExpenses: 0);
      final insight = savingsRateIndicatorRule(inputs);
      expect(insight!.message, contains('Good'));
      expect(insight.severity, InsightSeverity.positive);
    });

    test('Fair between 0% and 20% savings rate', () {
      final inputs = InsightInputs(income: 1000, expenses: 900, previousIncome: 0, previousExpenses: 0);
      final insight = savingsRateIndicatorRule(inputs);
      expect(insight!.message, contains('Fair'));
      expect(insight.severity, InsightSeverity.neutral);
    });

    test('Poor with a negative savings rate', () {
      final inputs = InsightInputs(income: 1000, expenses: 1500, previousIncome: 0, previousExpenses: 0);
      final insight = savingsRateIndicatorRule(inputs);
      expect(insight!.message, contains('Poor'));
      expect(insight.severity, InsightSeverity.warning);
    });
  });

  group('creditUtilizationIndicatorRule', () {
    test('Good under 30% utilization', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        creditUtilization: 0.2,
      );
      expect(creditUtilizationIndicatorRule(inputs)!.message, contains('Good'));
    });

    test('Fair between 30% and 75% utilization', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        creditUtilization: 0.5,
      );
      expect(creditUtilizationIndicatorRule(inputs)!.message, contains('Fair'));
    });

    test('Poor at or above 75% utilization', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        creditUtilization: 0.9,
      );
      expect(creditUtilizationIndicatorRule(inputs)!.message, contains('Poor'));
    });
  });

  group('debtTrendIndicatorRule', () {
    test('returns null with no previous debt figure', () {
      expect(debtTrendIndicatorRule(_zeroInputs), isNull);
    });

    test('Reducing when debt decreased', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        totalDebt: 800,
        previousTotalDebt: 1000,
      );
      final insight = debtTrendIndicatorRule(inputs);
      expect(insight!.message, contains('Reducing'));
      expect(insight.severity, InsightSeverity.positive);
    });

    test('Increasing when debt increased', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        totalDebt: 1200,
        previousTotalDebt: 1000,
      );
      final insight = debtTrendIndicatorRule(inputs);
      expect(insight!.message, contains('Increasing'));
      expect(insight.severity, InsightSeverity.warning);
    });

    test('Stable for a negligible change', () {
      final inputs = InsightInputs(
        income: 0,
        expenses: 0,
        previousIncome: 0,
        previousExpenses: 0,
        totalDebt: 1005,
        previousTotalDebt: 1000,
      );
      expect(debtTrendIndicatorRule(inputs)!.message, contains('Stable'));
    });
  });

  group('cashFlowTrendIndicatorRule', () {
    test('returns null with no previous net savings to compare against', () {
      expect(cashFlowTrendIndicatorRule(_zeroInputs), isNull);
    });

    test('Improving when net savings increased', () {
      final inputs = InsightInputs(income: 2000, expenses: 500, previousIncome: 1000, previousExpenses: 500);
      expect(cashFlowTrendIndicatorRule(inputs)!.message, contains('Improving'));
    });

    test('Declining when net savings decreased', () {
      final inputs = InsightInputs(income: 1000, expenses: 900, previousIncome: 1000, previousExpenses: 200);
      expect(cashFlowTrendIndicatorRule(inputs)!.message, contains('Declining'));
    });
  });

  group('spendingTrendIndicatorRule', () {
    test('returns null with no previous expenses to compare against', () {
      expect(spendingTrendIndicatorRule(_zeroInputs), isNull);
    });

    test('Up when expenses increased vs previous period', () {
      final inputs = InsightInputs(income: 0, expenses: 1200, previousIncome: 0, previousExpenses: 1000);
      final insight = spendingTrendIndicatorRule(inputs);
      expect(insight!.message, contains('Up'));
      expect(insight.severity, InsightSeverity.warning);
    });

    test('Down when expenses decreased vs previous period', () {
      final inputs = InsightInputs(income: 0, expenses: 800, previousIncome: 0, previousExpenses: 1000);
      final insight = spendingTrendIndicatorRule(inputs);
      expect(insight!.message, contains('Down'));
      expect(insight.severity, InsightSeverity.positive);
    });
  });

  group('rule lists', () {
    test('generalInsightRules and healthIndicatorRules contain the expected rules', () {
      expect(generalInsightRules, [
        netSavingsTrendRule,
        creditUtilizationRule,
        topSpendingCategoryRule,
        upcomingDueRule,
      ]);
      expect(healthIndicatorRules, [
        savingsRateIndicatorRule,
        creditUtilizationIndicatorRule,
        debtTrendIndicatorRule,
        cashFlowTrendIndicatorRule,
        spendingTrendIndicatorRule,
      ]);
    });
  });
}
