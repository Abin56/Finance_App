import 'package:finance_app/shared/domain/transaction_kind.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `TransactionKind` value must have a distinct, non-empty label —
/// this is the classification the whole `TransactionKindBadge` system
/// (Main History, Search, Person Statement context) is built on, so a
/// missing/duplicate case here would silently mislabel a row.
void main() {
  test('every TransactionKind has a non-empty label', () {
    for (final kind in TransactionKind.values) {
      expect(kind.label, isNotEmpty, reason: '$kind has no label');
    }
  });

  test('every TransactionKind label is unique', () {
    final labels = TransactionKind.values.map((k) => k.label).toSet();
    expect(labels.length, TransactionKind.values.length, reason: 'two kinds share a label');
  });

  test('every TransactionKind has an icon', () {
    for (final kind in TransactionKind.values) {
      expect(kind.icon, isNotNull, reason: '$kind has no icon');
    }
  });

  test('every TransactionKind has a color', () {
    for (final kind in TransactionKind.values) {
      expect(kind.color, isNotNull, reason: '$kind has no color');
    }
  });

  test('every TransactionKind has a unique, non-negative priority', () {
    final priorities = TransactionKind.values.map((k) => k.priority).toList();
    expect(priorities.every((p) => p >= 0), isTrue);
    expect(priorities.toSet().length, priorities.length, reason: 'two kinds share a priority');
  });

  test('analyticsKey matches the enum name, independent of the display label', () {
    for (final kind in TransactionKind.values) {
      expect(kind.analyticsKey, kind.name);
    }
  });

  group('specific labels match the requested taxonomy', () {
    final expected = {
      TransactionKind.myExpense: 'My Expense',
      TransactionKind.myIncome: 'Income',
      TransactionKind.transfer: 'Transfer',
      TransactionKind.splitExpense: 'Split Expense',
      TransactionKind.people: 'People',
      TransactionKind.bill: 'Bill',
      TransactionKind.creditCard: 'Credit Card',
      TransactionKind.loan: 'Loan',
      TransactionKind.emi: 'EMI',
    };

    for (final entry in expected.entries) {
      test('${entry.key} labels as "${entry.value}"', () {
        expect(entry.key.label, entry.value);
      });
    }
  });
}
