import 'package:finance_app/features/budget/domain/budget_insight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BudgetInsight.usageRatio', () {
    test('clamps to 1.0 when spent exceeds limit', () {
      final insight = BudgetInsight(
        limit: 1000,
        spent: 1500,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 1),
      );
      expect(insight.usageRatio, 1.0);
      expect(insight.isOverBudget, isTrue);
      expect(insight.remaining, -500);
    });

    test('is 0 without divide-by-zero when limit is 0', () {
      final insight = BudgetInsight(
        limit: 0,
        spent: 200,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 1),
      );
      expect(insight.usageRatio, 0);
      expect(insight.usageRatio.isNaN, isFalse);
    });
  });

  group('BudgetInsight.alertLevel', () {
    BudgetInsight insightFor(double ratio) => BudgetInsight(
      limit: 1000,
      spent: ratio * 1000,
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 1),
    );

    test('is none below 50%', () {
      expect(insightFor(0.49).alertLevel, BudgetAlertLevel.none);
    });

    test('is at50 from 50% up to 75%', () {
      expect(insightFor(0.50).alertLevel, BudgetAlertLevel.at50);
      expect(insightFor(0.74).alertLevel, BudgetAlertLevel.at50);
    });

    test('is at75 from 75% up to 90%', () {
      expect(insightFor(0.75).alertLevel, BudgetAlertLevel.at75);
      expect(insightFor(0.89).alertLevel, BudgetAlertLevel.at75);
    });

    test('is at90 from 90% up to 100%', () {
      expect(insightFor(0.90).alertLevel, BudgetAlertLevel.at90);
      expect(insightFor(0.99).alertLevel, BudgetAlertLevel.at90);
    });

    test('is at100 exactly at 100%', () {
      expect(insightFor(1.0).alertLevel, BudgetAlertLevel.at100);
    });

    test('is over beyond 100%', () {
      expect(insightFor(1.2).alertLevel, BudgetAlertLevel.over);
    });
  });

  group('BudgetInsight daily period math', () {
    test('totalDays is 1 and daysRemaining is 0 for a same-day period', () {
      final today = DateTime(2026, 1, 15);
      final insight = BudgetInsight(
        limit: 200,
        spent: 80,
        periodStart: today,
        periodEnd: today,
        now: today,
      );

      expect(insight.totalDays, 1);
      expect(insight.daysElapsed, 1);
      expect(insight.daysRemaining, 0);
      expect(insight.averageDailySpend, 80);
      expect(insight.averageDailyBudgetRemaining, 0);
      expect(insight.predictedTotalSpend, 80);
      expect(insight.predictedToExceedBudget, isFalse);
    });
  });

  group('BudgetInsight monthly period math', () {
    test('computes days elapsed/remaining and projected spend mid-month', () {
      // January 2026 has 31 days. "Now" is Jan 10 -> 10 days elapsed, 21 remaining.
      final insight = BudgetInsight(
        limit: 3100,
        spent: 1000,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
        now: DateTime(2026, 1, 10),
      );

      expect(insight.totalDays, 31);
      expect(insight.daysElapsed, 10);
      expect(insight.daysRemaining, 21);
      expect(insight.averageDailySpend, 100);
      expect(insight.remaining, 2100);
      expect(insight.averageDailyBudgetRemaining, closeTo(100, 0.001));
      expect(insight.predictedTotalSpend, closeTo(3100, 0.001));
      expect(insight.predictedToExceedBudget, isFalse);
    });

    test('flags a predicted overspend when pace exceeds the limit', () {
      final insight = BudgetInsight(
        limit: 1000,
        spent: 600,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
        now: DateTime(2026, 1, 10),
      );

      // averageDailySpend = 60, predictedTotalSpend = 60 * 31 = 1860 > 1000
      expect(insight.predictedTotalSpend, closeTo(1860, 0.001));
      expect(insight.predictedToExceedBudget, isTrue);
    });

    test('clamps daysElapsed to totalDays when now is after the period end', () {
      final insight = BudgetInsight(
        limit: 1000,
        spent: 900,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
        now: DateTime(2026, 2, 15),
      );

      expect(insight.daysElapsed, 31);
      expect(insight.daysRemaining, 0);
      expect(insight.averageDailyBudgetRemaining, 0);
    });
  });
}
