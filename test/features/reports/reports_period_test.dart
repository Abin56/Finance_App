import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportsPeriod.financialYear.rangeFor', () {
    test('January start month collapses to the calendar year', () {
      final now = DateTime(2026, 7, 7);
      final range = ReportsPeriod.financialYear.rangeFor(now, fiscalYearStartMonth: 1);

      expect(range.start, DateTime(2026, 1, 1));
      expect(range.end.year, 2026);
      expect(range.end.month, 12);
      expect(range.end.day, 31);
    });

    test('April start month, date after April, runs Apr this year to Mar next year', () {
      final now = DateTime(2026, 7, 7);
      final range = ReportsPeriod.financialYear.rangeFor(now, fiscalYearStartMonth: 4);

      expect(range.start, DateTime(2026, 4, 1));
      expect(range.end.year, 2027);
      expect(range.end.month, 3);
      expect(range.end.day, 31);
    });

    test('April start month, date before April (January), runs previous Apr to this Mar', () {
      final now = DateTime(2026, 1, 15);
      final range = ReportsPeriod.financialYear.rangeFor(now, fiscalYearStartMonth: 4);

      expect(range.start, DateTime(2025, 4, 1));
      expect(range.end.year, 2026);
      expect(range.end.month, 3);
      expect(range.end.day, 31);
    });

    test('defaults to fiscalYearStartMonth 1 when not passed', () {
      final now = DateTime(2026, 3, 1);
      final range = ReportsPeriod.financialYear.rangeFor(now);
      expect(range.start, DateTime(2026, 1, 1));
    });
  });

  group('ReportsPeriod.today.rangeFor', () {
    test('spans just the given day', () {
      final now = DateTime(2026, 7, 7, 14, 30);
      final range = ReportsPeriod.today.rangeFor(now);

      expect(range.contains(DateTime(2026, 7, 7, 0, 0)), isTrue);
      expect(range.contains(DateTime(2026, 7, 7, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 7, 8, 0, 0)), isFalse);
    });
  });

  group('ReportsPeriod.thisWeek.rangeFor', () {
    test('spans Monday-start week containing the given day', () {
      final tuesday = DateTime(2026, 7, 7); // 2026-07-07 is a Tuesday
      final range = ReportsPeriod.thisWeek.rangeFor(tuesday);

      expect(range.start.weekday, DateTime.monday);
      expect(range.contains(tuesday), isTrue);
    });
  });
}
