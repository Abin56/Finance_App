import 'package:finance_app/features/credit_cards/domain/credit_card_profile.dart';
import 'package:finance_app/features/credit_cards/domain/statement_period.dart';
import 'package:flutter_test/flutter_test.dart';

CreditCardProfile _card({int statementDay = 17, int paymentDueDay = 5, double creditLimit = 100000}) {
  return CreditCardProfile(
    id: 'card1',
    accountId: 'acc1',
    statementDay: statementDay,
    paymentDueDay: paymentDueDay,
    creditLimit: creditLimit,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('StatementPeriodCalculator — the milestone\'s worked example', () {
    test('18 Jun -> 17 Jul cycle, generated 17 Jul, due 5 Aug', () {
      final card = _card(statementDay: 17, paymentDueDay: 5);

      // "now" is inside the cycle that started 18 Jun and closes 17 Jul.
      final period = StatementPeriodCalculator.currentCycleFor(card, now: DateTime(2026, 7, 10));

      expect(period.periodStart, DateTime(2026, 6, 18));
      expect(period.periodEnd, DateTime(2026, 7, 17));
      expect(period.dueDate, DateTime(2026, 8, 5));
    });

    test('the day after the statement date rolls into the next cycle', () {
      final card = _card(statementDay: 17, paymentDueDay: 5);

      final period = StatementPeriodCalculator.currentCycleFor(card, now: DateTime(2026, 7, 18));

      expect(period.periodStart, DateTime(2026, 7, 18));
      expect(period.periodEnd, DateTime(2026, 8, 17));
    });

    test('Milestone 14 Task 4 — Next Statement is 18 Jul -> 17 Aug once the current cycle has closed', () {
      final card = _card(statementDay: 17, paymentDueDay: 5);

      // The cycle that was "current" while inside 18 Jun-17 Jul is now
      // closed; the "next statement" (what mostRecentClosedCycleFor's
      // caller would see as upcoming) is 18 Jul -> 17 Aug.
      final nextStatement = StatementPeriodCalculator.currentCycleFor(card, now: DateTime(2026, 7, 25));

      expect(nextStatement.periodStart, DateTime(2026, 7, 18));
      expect(nextStatement.periodEnd, DateTime(2026, 8, 17));
      expect(nextStatement.dueDate, DateTime(2026, 9, 5));
    });

    test('exactly on the statement date is still the closing cycle', () {
      final card = _card(statementDay: 17, paymentDueDay: 5);

      final period = StatementPeriodCalculator.currentCycleFor(card, now: DateTime(2026, 7, 17));

      expect(period.periodEnd, DateTime(2026, 7, 17));
    });
  });

  group('StatementPeriodCalculator — month clamping', () {
    test('statement day 31 clamps to February\'s last day', () {
      final card = _card(statementDay: 31, paymentDueDay: 5);

      final period = StatementPeriodCalculator.currentCycleFor(card, now: DateTime(2026, 2, 20));

      expect(period.periodEnd, DateTime(2026, 2, 28));
    });

    test('due day 31 clamps in a 30-day month', () {
      final card = _card(statementDay: 17, paymentDueDay: 31);

      final period = StatementPeriodCalculator.currentCycleFor(card, now: DateTime(2026, 4, 1));

      // Statement closes 17 Apr; due date falls in May, clamped to 31 (May has 31 days).
      expect(period.dueDate, DateTime(2026, 5, 31));
    });

    test('due day 31 clamps into a 30-day due month', () {
      final card = _card(statementDay: 5, paymentDueDay: 31);

      // Statement closes 5 Nov; due date falls in December (31 days, no clamp needed)
      // vs. a case where the due month is April (30 days).
      final period = StatementPeriodCalculator.currentCycleFor(card, now: DateTime(2026, 3, 1));
      // Statement closes 5 Mar; due date falls in April, clamped to 30.
      expect(period.dueDate, DateTime(2026, 4, 30));
    });
  });

  group('StatementPeriodCalculator.mostRecentClosedCycleFor', () {
    test('returns the cycle whose periodEnd has already passed', () {
      final card = _card(statementDay: 17, paymentDueDay: 5);

      final closed = StatementPeriodCalculator.mostRecentClosedCycleFor(card, now: DateTime(2026, 7, 20));

      expect(closed.periodEnd, DateTime(2026, 7, 17));
    });

    test('returns today\'s cycle when the statement date is exactly today', () {
      final card = _card(statementDay: 17, paymentDueDay: 5);

      final closed = StatementPeriodCalculator.mostRecentClosedCycleFor(card, now: DateTime(2026, 7, 17));

      expect(closed.periodEnd, DateTime(2026, 7, 17));
    });

    test('returns the prior cycle when the current one has not closed yet', () {
      final card = _card(statementDay: 17, paymentDueDay: 5);

      final closed = StatementPeriodCalculator.mostRecentClosedCycleFor(card, now: DateTime(2026, 7, 10));

      expect(closed.periodEnd, DateTime(2026, 6, 17));
    });
  });

  group('StatementPeriod.contains', () {
    test('includes both endpoints and excludes days outside the window', () {
      final period = StatementPeriod(
        periodStart: DateTime(2026, 6, 18),
        periodEnd: DateTime(2026, 7, 17),
        dueDate: DateTime(2026, 8, 5),
      );

      expect(period.contains(DateTime(2026, 6, 18)), isTrue);
      expect(period.contains(DateTime(2026, 7, 17)), isTrue);
      expect(period.contains(DateTime(2026, 7, 1)), isTrue);
      expect(period.contains(DateTime(2026, 6, 17)), isFalse);
      expect(period.contains(DateTime(2026, 7, 18)), isFalse);
    });
  });
}
