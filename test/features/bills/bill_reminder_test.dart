import 'package:finance_app/features/bills/domain/bill.dart';
import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:finance_app/features/bills/domain/bill_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill makeBill({required DateTime dueDate, List<int> reminderOffsets = const []}) {
    return Bill(
      id: 'b1',
      name: 'Electricity',
      amount: 100,
      dueDate: dueDate,
      recurrence: BillRecurrence.monthly,
      createdAt: DateTime(2026, 1, 1),
      reminderOffsets: reminderOffsets,
    );
  }

  final now = DateTime(2026, 3, 10);

  group('BillReminder.daysUntilDue', () {
    test('is 0 when due today', () {
      final bill = makeBill(dueDate: DateTime(2026, 3, 10));
      expect(BillReminder(bill: bill, now: now).daysUntilDue, 0);
    });

    test('is positive for a future due date', () {
      final bill = makeBill(dueDate: DateTime(2026, 3, 17));
      expect(BillReminder(bill: bill, now: now).daysUntilDue, 7);
    });

    test('is negative for a past due date', () {
      final bill = makeBill(dueDate: DateTime(2026, 3, 5));
      expect(BillReminder(bill: bill, now: now).daysUntilDue, -5);
    });
  });

  group('BillReminder.isDueToday', () {
    test('is true when an offset matches daysUntilDue exactly', () {
      final bill = makeBill(dueDate: DateTime(2026, 3, 13), reminderOffsets: const [1, 3, 7]);
      expect(BillReminder(bill: bill, now: now).isDueToday, isTrue);
    });

    test('is false when no offset matches', () {
      final bill = makeBill(dueDate: DateTime(2026, 3, 20), reminderOffsets: const [1, 3, 7]);
      expect(BillReminder(bill: bill, now: now).isDueToday, isFalse);
    });

    test('is false when reminderOffsets is empty', () {
      final bill = makeBill(dueDate: DateTime(2026, 3, 10), reminderOffsets: const []);
      expect(BillReminder(bill: bill, now: now).isDueToday, isFalse);
    });
  });

  group('BillReminder.labelForOffset', () {
    test('labels 0 as Today', () {
      expect(BillReminder.labelForOffset(0), 'Today');
    });

    test('labels 1 as Tomorrow', () {
      expect(BillReminder.labelForOffset(1), 'Tomorrow');
    });

    test('labels any other value as "N days before"', () {
      expect(BillReminder.labelForOffset(3), '3 days before');
      expect(BillReminder.labelForOffset(14), '14 days before');
    });
  });

  group('BillReminder.dueOffsetLabels', () {
    test('returns every offset label due today', () {
      final bill = makeBill(dueDate: DateTime(2026, 3, 10), reminderOffsets: const [0]);
      expect(BillReminder(bill: bill, now: now).dueOffsetLabels, ['Today']);
    });

    test('returns an empty list when nothing is due today', () {
      final bill = makeBill(dueDate: DateTime(2026, 4, 1), reminderOffsets: const [0, 1, 3, 7]);
      expect(BillReminder(bill: bill, now: now).dueOffsetLabels, isEmpty);
    });
  });
}
