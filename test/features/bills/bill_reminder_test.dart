import 'package:finance_app/features/bills/domain/bill_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 3, 10);

  group('BillReminder.daysUntilDue', () {
    test('is 0 when due today', () {
      expect(BillReminder(dueDate: DateTime(2026, 3, 10), reminderOffsets: const [], now: now).daysUntilDue, 0);
    });

    test('is positive for a future due date', () {
      expect(BillReminder(dueDate: DateTime(2026, 3, 17), reminderOffsets: const [], now: now).daysUntilDue, 7);
    });

    test('is negative for a past due date', () {
      expect(BillReminder(dueDate: DateTime(2026, 3, 5), reminderOffsets: const [], now: now).daysUntilDue, -5);
    });
  });

  group('BillReminder.isDueToday', () {
    test('is true when an offset matches daysUntilDue exactly', () {
      final reminder = BillReminder(dueDate: DateTime(2026, 3, 13), reminderOffsets: const [1, 3, 7], now: now);
      expect(reminder.isDueToday, isTrue);
    });

    test('is false when no offset matches', () {
      final reminder = BillReminder(dueDate: DateTime(2026, 3, 20), reminderOffsets: const [1, 3, 7], now: now);
      expect(reminder.isDueToday, isFalse);
    });

    test('is false when reminderOffsets is empty', () {
      final reminder = BillReminder(dueDate: DateTime(2026, 3, 10), reminderOffsets: const [], now: now);
      expect(reminder.isDueToday, isFalse);
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
      final reminder = BillReminder(dueDate: DateTime(2026, 3, 10), reminderOffsets: const [0], now: now);
      expect(reminder.dueOffsetLabels, ['Today']);
    });

    test('returns an empty list when nothing is due today', () {
      final reminder = BillReminder(dueDate: DateTime(2026, 4, 1), reminderOffsets: const [0, 1, 3, 7], now: now);
      expect(reminder.dueOffsetLabels, isEmpty);
    });
  });
}
