import 'package:finance_app/features/expense/domain/expense.dart';
import 'package:finance_app/features/expense/domain/expense_participant.dart';
import 'package:finance_app/features/expense/domain/split_type.dart';
import 'package:flutter_test/flutter_test.dart';

Expense _expense({required SplitType splitType, required List<ExpenseParticipant> participants}) {
  return Expense(
    id: 'exp1',
    description: 'Dinner',
    totalAmount: 100,
    date: DateTime(2026, 1, 1),
    categoryId: 'cat1',
    accountId: 'acc1',
    transactionId: 'txn1',
    splitType: splitType,
    participants: participants,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('Expense.canReassign', () {
    test('an untouched old expense transaction (no linked Expense at all) can be assigned/split', () {
      expect(Expense.canReassign(expense: null, isExpenseTransaction: true), true);
    });

    test('a plain unsplit Expense (SplitType.none, no participants) can still be assigned/split', () {
      final expense = _expense(splitType: SplitType.none, participants: const []);
      expect(Expense.canReassign(expense: expense, isExpenseTransaction: true), true);
    });

    test('an already-assigned expense (one non-Me participant) cannot be reassigned again', () {
      final expense = _expense(
        splitType: SplitType.custom,
        participants: [ExpenseParticipant(name: 'Rahul', share: 100, personId: 'p1')],
      );
      expect(Expense.canReassign(expense: expense, isExpenseTransaction: true), false);
    });

    test('an already-split expense (multiple participants) cannot be reassigned again', () {
      final expense = _expense(
        splitType: SplitType.equal,
        participants: [
          ExpenseParticipant(name: 'Rahul', share: 50, personId: 'p1'),
          ExpenseParticipant(name: 'Arjun', share: 50, personId: 'p2'),
        ],
      );
      expect(Expense.canReassign(expense: expense, isExpenseTransaction: true), false);
    });

    test('a non-expense transaction (income) can never be assigned/split, regardless of any Expense link', () {
      expect(Expense.canReassign(expense: null, isExpenseTransaction: false), false);
    });

    test('a split_type that carries no participants (legacy/degenerate data) still counts as reassignable', () {
      // isSplit requires splitType != none AND participants.isNotEmpty — a
      // stray splitType with an empty participant list (e.g. a conversion
      // that was interrupted) must not permanently lock out assign/split.
      final expense = _expense(splitType: SplitType.equal, participants: const []);
      expect(Expense.canReassign(expense: expense, isExpenseTransaction: true), true);
    });
  });
}
