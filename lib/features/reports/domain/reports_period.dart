import '../../../core/extensions/date_extensions.dart';

/// Time window a report can be scoped to — drives both the Reports
/// dashboard's overview cards and the category detail screen's trend chart.
enum ReportsPeriod { today, thisWeek, thisMonth, lastMonth, thisYear, financialYear, custom }

extension ReportsPeriodX on ReportsPeriod {
  String get label {
    switch (this) {
      case ReportsPeriod.today:
        return 'Today';
      case ReportsPeriod.thisWeek:
        return 'This Week';
      case ReportsPeriod.thisMonth:
        return 'This Month';
      case ReportsPeriod.lastMonth:
        return 'Last Month';
      case ReportsPeriod.thisYear:
        return 'This Year';
      case ReportsPeriod.financialYear:
        return 'Financial Year';
      case ReportsPeriod.custom:
        return 'Custom';
    }
  }

  /// Inclusive start/end for this period, relative to [now]. [custom]
  /// has no inherent range — callers must supply their own picked range
  /// and never call this getter for it. [financialYear] needs the user's
  /// configured start month (see `fiscalYearStartMonthProvider`) since this
  /// app has no hardcoded fiscal-year convention — pass 1 for a plain
  /// calendar-year window.
  DateRange rangeFor(DateTime now, {int fiscalYearStartMonth = 1}) {
    switch (this) {
      case ReportsPeriod.today:
        return DateRange(now.dateOnly, now.dateOnly.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
      case ReportsPeriod.thisWeek:
        return DateRange(now.startOfWeek, now.endOfWeek);
      case ReportsPeriod.thisMonth:
        return DateRange(now.startOfMonth, now.endOfMonth);
      case ReportsPeriod.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1);
        return DateRange(lastMonth.startOfMonth, lastMonth.endOfMonth);
      case ReportsPeriod.thisYear:
        return DateRange(DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
      case ReportsPeriod.financialYear:
        final fyStartYear = now.month >= fiscalYearStartMonth ? now.year : now.year - 1;
        final start = DateTime(fyStartYear, fiscalYearStartMonth, 1);
        final end = DateTime(fyStartYear + 1, fiscalYearStartMonth, 1).subtract(const Duration(seconds: 1));
        return DateRange(start, end);
      case ReportsPeriod.custom:
        throw UnsupportedError('ReportsPeriod.custom has no inherent range');
    }
  }
}

class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime dateTime) => !dateTime.isBefore(start) && !dateTime.isAfter(end);
}
