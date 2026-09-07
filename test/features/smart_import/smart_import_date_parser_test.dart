import 'package:finance_app/features/smart_import/domain/smart_import_date_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed "today" so year-inference assertions never depend on the machine
  // clock.
  final reference = DateTime(2026, 9, 7);

  group('SmartImportDateParser', () {
    test('parses "05 Sep" with no year, inferring the reference year', () {
      final result = SmartImportDateParser.tryParse(
        '05 Sep',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 5));
      expect(result?.hasExplicitYear, isFalse);
    });

    test('parses "Sep 05" (month first)', () {
      final result = SmartImportDateParser.tryParse(
        'Sep 05',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 5));
    });

    test('parses "05 Sep 2026" with an explicit year', () {
      final result = SmartImportDateParser.tryParse(
        '05 Sep 2026',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 5));
      expect(result?.hasExplicitYear, isTrue);
    });

    test('parses "05/09/2026" as day/month/year', () {
      final result = SmartImportDateParser.tryParse(
        '05/09/2026',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 5));
    });

    test('parses "05-09-26" with a 2-digit year', () {
      final result = SmartImportDateParser.tryParse(
        '05-09-26',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 5));
    });

    test('flips to month-first when the first number cannot be a month', () {
      // 25 can't be a month, so it must be the day even though it comes first.
      final result = SmartImportDateParser.tryParse(
        '25/09/2026',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 25));
    });

    test(
      'flips to month-first when the second number cannot be a day-first month',
      () {
        final result = SmartImportDateParser.tryParse(
          '09/25/2026',
          referenceDate: reference,
        );
        expect(result?.date, DateTime(2026, 9, 25));
      },
    );

    test(
      'infers the previous year when the month/day would otherwise be in the future',
      () {
        // "today" is 7 Sep 2026 — a bare "20 Dec" on a screenshot with no year
        // almost certainly means the December just gone, not one 3+ months away.
        final result = SmartImportDateParser.tryParse(
          '20 Dec',
          referenceDate: reference,
        );
        expect(result?.date, DateTime(2025, 12, 20));
        expect(result?.hasExplicitYear, isFalse);
      },
    );

    test('returns null for text with no date-shaped content', () {
      expect(
        SmartImportDateParser.tryParse('SWIGGY ₹420', referenceDate: reference),
        isNull,
      );
    });

    test('returns null for an out-of-range day', () {
      expect(
        SmartImportDateParser.tryParse('35 Sep', referenceDate: reference),
        isNull,
      );
    });

    test(
      'does not mistake a 3-digit amount right after the date for a year',
      () {
        // Regression: pasted text where an amount immediately follows the
        // date with no merchant in between ("06 Sep 420 DR") used to parse
        // "420" as a 3-digit year, producing the nonsense date 0420-09-06 —
        // a real year is always written with exactly 2 or 4 digits.
        final result = SmartImportDateParser.tryParse(
          '06 Sep 420 DR',
          referenceDate: reference,
        );
        expect(result?.date, DateTime(2026, 9, 6));
        expect(result?.hasExplicitYear, isFalse);
      },
    );

    test(
      'does not mistake a 1-digit trailing number for a year (month-first)',
      () {
        final result = SmartImportDateParser.tryParse(
          'Sep 06 5 DR',
          referenceDate: reference,
        );
        expect(result?.date, DateTime(2026, 9, 6));
        expect(result?.hasExplicitYear, isFalse);
      },
    );

    test(
      'still accepts a genuine 2-digit and 4-digit year next to other text',
      () {
        expect(
          SmartImportDateParser.tryParse(
            '05 Sep 26 SWIGGY',
            referenceDate: reference,
          )?.date,
          DateTime(2026, 9, 5),
        );
        expect(
          SmartImportDateParser.tryParse(
            '05 Sep 2026 SWIGGY',
            referenceDate: reference,
          )?.date,
          DateTime(2026, 9, 5),
        );
      },
    );

    test(
      'parses "05-Sep-26" (hyphen-joined, as HDFC/ICICI SMS alerts write it)',
      () {
        final result = SmartImportDateParser.tryParse(
          '05-Sep-26',
          referenceDate: reference,
        );
        expect(result?.date, DateTime(2026, 9, 5));
      },
    );

    test('parses "05-SEP-2026" (hyphen-joined, explicit 4-digit year)', () {
      final result = SmartImportDateParser.tryParse(
        '05-SEP-2026',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 5));
    });

    test('parses "Sep-05-2026" (month-first, hyphen-joined)', () {
      final result = SmartImportDateParser.tryParse(
        'Sep-05-2026',
        referenceDate: reference,
      );
      expect(result?.date, DateTime(2026, 9, 5));
    });

    test(
      'does not mistake a 3-digit amount right after a hyphen-joined date for a year',
      () {
        // Same regression as the space-separated case above, but for the
        // hyphen-joined "05-Sep-26" shape banks actually send.
        final result = SmartImportDateParser.tryParse(
          '05-Sep-420 DR',
          referenceDate: reference,
        );
        expect(result?.date, DateTime(2026, 9, 5));
        expect(result?.hasExplicitYear, isFalse);
      },
    );
  });
}
