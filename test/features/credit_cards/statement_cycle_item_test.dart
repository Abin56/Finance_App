import 'package:finance_app/features/credit_cards/domain/statement.dart';
import 'package:finance_app/features/credit_cards/domain/statement_cycle_item.dart';
import 'package:finance_app/features/credit_cards/domain/statement_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for `StatementCycleItem`, the `CycleItem` adapter Credit Cards
/// wraps a `Statement` in before handing it to `CycleEngine.classifyForCarryForward`.
void main() {
  Statement statement({
    double totalAmount = 1000,
    double amountPaid = 0,
    required DateTime dueDate,
    DateTime? periodEnd,
  }) {
    return Statement(
      id: 's1',
      cardId: 'c1',
      periodStart: DateTime(2026, 6, 18),
      periodEnd: periodEnd ?? DateTime(2026, 7, 17),
      generatedDate: periodEnd ?? DateTime(2026, 7, 17),
      dueDate: dueDate,
      totalAmount: totalAmount,
      createdAt: DateTime(2026, 7, 17),
      amountPaid: amountPaid,
    );
  }

  group('StatementCycleItem', () {
    test('isSettled is true when remainingAmount is fully paid', () {
      final item = StatementCycleItem(
        statement(totalAmount: 1000, amountPaid: 1000, dueDate: DateTime(2020, 1, 1)),
      );
      expect(item.isSettled, isTrue);
    });

    test('isSettled is false while any amount remains, including partial payment', () {
      final item = StatementCycleItem(
        statement(totalAmount: 1000, amountPaid: 400, dueDate: DateTime(2020, 1, 1)),
      );
      expect(item.isSettled, isFalse);
    });

    test('isOverdue matches Statement.status == overdue for an unpaid past-due statement', () {
      final s = statement(totalAmount: 1000, amountPaid: 0, dueDate: DateTime(2020, 1, 1));
      final item = StatementCycleItem(s);
      expect(s.status, StatementStatus.overdue);
      expect(item.isOverdue, isTrue);
    });

    test('isOverdue is false for a fully paid statement even if its due date is in the past', () {
      // Before the fix, isOverdue independently re-derived "overdue" from
      // dueDate vs DateTime.now(), disagreeing with Statement.status once
      // paid. Both must now agree.
      final s = statement(totalAmount: 1000, amountPaid: 1000, dueDate: DateTime(2020, 1, 1));
      final item = StatementCycleItem(s);
      expect(item.isSettled, isTrue);
      expect(item.isOverdue, isFalse);
    });

    test('isOverdue is false for a statement not yet due', () {
      final s = statement(totalAmount: 1000, amountPaid: 0, dueDate: DateTime(2099, 1, 1));
      final item = StatementCycleItem(s);
      expect(item.isOverdue, isFalse);
    });

    test('cycleDate is the statement\'s periodEnd', () {
      final periodEnd = DateTime(2026, 7, 17);
      final item = StatementCycleItem(
        statement(dueDate: DateTime(2026, 8, 5), periodEnd: periodEnd),
      );
      expect(item.cycleDate, periodEnd);
    });

    test('carryForwardEligible defaults to true', () {
      final item = StatementCycleItem(statement(dueDate: DateTime(2026, 8, 5)));
      expect(item.carryForwardEligible, isTrue);
    });
  });
}
