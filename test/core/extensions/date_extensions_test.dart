import 'package:finance_app/core/extensions/date_extensions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateTimeX.isSameWeek', () {
    test('dates within the same Monday-start week are the same week', () {
      // 2026-01-05 is a Monday.
      final monday = DateTime(2026, 1, 5);
      final wednesday = DateTime(2026, 1, 7);
      final sunday = DateTime(2026, 1, 11);

      expect(monday.isSameWeek(wednesday), isTrue);
      expect(sunday.isSameWeek(monday), isTrue);
    });

    test('the day before Monday belongs to the prior week', () {
      final sundayBefore = DateTime(2026, 1, 4);
      final mondayAfter = DateTime(2026, 1, 5);

      expect(sundayBefore.isSameWeek(mondayAfter), isFalse);
    });

    test('the following Monday belongs to the next week', () {
      final thisMonday = DateTime(2026, 1, 5);
      final nextMonday = DateTime(2026, 1, 12);

      expect(thisMonday.isSameWeek(nextMonday), isFalse);
    });

    test('is reflexive for the same date', () {
      final date = DateTime(2026, 1, 7);
      expect(date.isSameWeek(date), isTrue);
    });
  });
}
