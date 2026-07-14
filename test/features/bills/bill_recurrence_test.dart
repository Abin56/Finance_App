import 'package:finance_app/features/bills/domain/bill_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BillRecurrence.nextDueDate', () {
    test('oneTime returns the same date unchanged', () {
      final date = DateTime(2026, 3, 15);
      expect(BillRecurrence.oneTime.nextDueDate(date), date);
    });

    test('daily adds 1 day', () {
      expect(BillRecurrence.daily.nextDueDate(DateTime(2026, 3, 15)), DateTime(2026, 3, 16));
    });

    test('weekly adds 7 days', () {
      expect(BillRecurrence.weekly.nextDueDate(DateTime(2026, 3, 15)), DateTime(2026, 3, 22));
    });

    test('monthly adds a calendar month', () {
      expect(BillRecurrence.monthly.nextDueDate(DateTime(2026, 3, 15)), DateTime(2026, 4, 15));
    });

    test('monthly clamps to the last day of a shorter target month', () {
      // Jan 31 -> Feb has 28 days in 2026 (not a leap year).
      expect(BillRecurrence.monthly.nextDueDate(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
    });

    test('monthly clamps correctly across a leap year February', () {
      // 2028 is a leap year -> Feb has 29 days.
      expect(BillRecurrence.monthly.nextDueDate(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
    });

    test('monthly rolls over into the next year at December', () {
      expect(BillRecurrence.monthly.nextDueDate(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
    });

    test('yearly adds 12 months, preserving day/month', () {
      expect(BillRecurrence.yearly.nextDueDate(DateTime(2026, 3, 15)), DateTime(2027, 3, 15));
    });

    test('yearly clamps Feb 29 on a leap year to Feb 28 the next (non-leap) year', () {
      expect(BillRecurrence.yearly.nextDueDate(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
    });

    test('custom adds the given number of days', () {
      expect(
        BillRecurrence.custom.nextDueDate(DateTime(2026, 3, 15), customDays: 10),
        DateTime(2026, 3, 25),
      );
    });

    test('custom defaults to 1 day when customDays is not provided', () {
      expect(BillRecurrence.custom.nextDueDate(DateTime(2026, 3, 15)), DateTime(2026, 3, 16));
    });
  });

  group('BillRecurrenceX.fromName', () {
    test('round-trips every value through its name', () {
      for (final recurrence in BillRecurrence.values) {
        expect(BillRecurrenceX.fromName(recurrence.name), recurrence);
      }
    });

    test('falls back to oneTime for an unknown name', () {
      expect(BillRecurrenceX.fromName('unknown'), BillRecurrence.oneTime);
    });
  });
}
