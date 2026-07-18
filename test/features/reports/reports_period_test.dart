import 'package:finance_app/features/reports/domain/reports_period.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _transaction({
  required DateTime dateTime,
  DateTime? accountingMonth,
  double amount = 100,
}) {
  return Transaction(
    id: 't1',
    type: TransactionType.expense,
    amount: amount,
    dateTime: dateTime,
    accountId: 'acc1',
    categoryId: 'cat1',
    createdAt: dateTime,
    accountingMonth: accountingMonth,
  );
}

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

  group('ReportsPeriodX.reportDateFor', () {
    test('thisMonth reads effectiveMonth (accounting month) when set, not the real date', () {
      final t = _transaction(dateTime: DateTime(2026, 6, 15), accountingMonth: DateTime(2026, 7));

      expect(ReportsPeriod.thisMonth.reportDateFor(t), DateTime(2026, 7));
    });

    test('lastMonth also reads effectiveMonth — both month-granular periods behave the same', () {
      final t = _transaction(dateTime: DateTime(2026, 6, 15), accountingMonth: DateTime(2026, 7));

      expect(ReportsPeriod.lastMonth.reportDateFor(t), DateTime(2026, 7));
    });

    test('falls back to dateTime when no accounting month is set, for a month-granular period', () {
      final t = _transaction(dateTime: DateTime(2026, 6, 15));

      expect(ReportsPeriod.thisMonth.reportDateFor(t), DateTime(2026, 6));
    });

    test('non-month-granular periods (today/week/year/financialYear) always use the real dateTime', () {
      final t = _transaction(dateTime: DateTime(2026, 6, 15, 9, 30), accountingMonth: DateTime(2026, 7));

      expect(ReportsPeriod.today.reportDateFor(t), DateTime(2026, 6, 15, 9, 30));
      expect(ReportsPeriod.thisWeek.reportDateFor(t), DateTime(2026, 6, 15, 9, 30));
      expect(ReportsPeriod.thisYear.reportDateFor(t), DateTime(2026, 6, 15, 9, 30));
      expect(ReportsPeriod.financialYear.reportDateFor(t), DateTime(2026, 6, 15, 9, 30));
    });
  });

  group('Month-boundary regression — rangeFor + reportDateFor composed together', () {
    test('a transaction dated the last second of last month but reassigned to this month is included', () {
      final now = DateTime(2026, 7, 15);
      final range = ReportsPeriod.thisMonth.rangeFor(now);
      final t = _transaction(dateTime: DateTime(2026, 6, 30, 23, 59, 59), accountingMonth: DateTime(2026, 7));

      expect(range.contains(ReportsPeriod.thisMonth.reportDateFor(t)), isTrue);
    });

    test('a transaction dated the first second of this month but reassigned to last month is excluded', () {
      final now = DateTime(2026, 7, 15);
      final range = ReportsPeriod.thisMonth.rangeFor(now);
      final t = _transaction(dateTime: DateTime(2026, 7, 1, 0, 0, 1), accountingMonth: DateTime(2026, 6));

      expect(range.contains(ReportsPeriod.thisMonth.reportDateFor(t)), isFalse);
    });

    test('with no accounting month, a transaction exactly on the month boundary follows its real date', () {
      final now = DateTime(2026, 7, 15);
      final range = ReportsPeriod.thisMonth.rangeFor(now);

      final lastSecondOfJune = _transaction(dateTime: DateTime(2026, 6, 30, 23, 59, 59));
      final firstSecondOfJuly = _transaction(dateTime: DateTime(2026, 7, 1, 0, 0, 0));

      expect(range.contains(ReportsPeriod.thisMonth.reportDateFor(lastSecondOfJune)), isFalse);
      expect(range.contains(ReportsPeriod.thisMonth.reportDateFor(firstSecondOfJuly)), isTrue);
    });
  });
}
