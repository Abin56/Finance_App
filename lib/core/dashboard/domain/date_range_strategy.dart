import '../../extensions/date_extensions.dart';
import '../../../features/reports/domain/reports_period.dart';

/// How a dashboard widget picks its date window. Every strategy is a pure
/// function of "now" (plus its own parameters) → [DateRange] — no strategy
/// reads a repository or holds state, so [resolve] is cheap to call on
/// every rebuild and safe to cache by (strategy, day) in a [Result].
///
/// New strategies (Weekly, Yearly, a second Custom variant, …) are added by
/// adding a case here and to [DateRangeStrategyX.resolve]/[label] — nothing
/// outside this file (no widget, no calculator) needs to change, since every
/// caller only ever sees the resolved [DateRange].
sealed class DateRangeStrategy {
  const DateRangeStrategy();
}

/// Rolls forward daily: from the [anchorDay]th of the previous applicable
/// month through today. This is "Case 1" — a salary-cycle window that always
/// ends on today's date, so it grows by one day every day and resets back to
/// a single day the moment today passes the next [anchorDay].
///
/// Example with anchorDay=17: on 8 Aug this resolves to 17 Jul → 8 Aug; on
/// 18 Aug (today has passed the 17th) it becomes 17 Aug → 18 Aug.
class SalaryCycleToDate extends DateRangeStrategy {
  const SalaryCycleToDate({this.anchorDay = 17});

  /// Day of month (1-28, to stay valid in February) the cycle starts on.
  final int anchorDay;
}

/// A single complete cycle window: [anchorDay] of one month through
/// [anchorDay] of the next — "Case 2". Which cycle is "current" depends on
/// where today falls relative to [anchorDay]: if today is on/after the
/// anchor day, the current cycle started this month and ends next month; if
/// today is before the anchor day, the current cycle started last month and
/// ends this month. Either way today always falls inside the returned range.
///
/// Example with anchorDay=17: on 8 Aug (before the 17th) this resolves to
/// 17 Jul → 17 Aug; on 18 Aug (on/after the 17th) it resolves to
/// 17 Aug → 17 Sep.
class SalaryCycleFull extends DateRangeStrategy {
  const SalaryCycleFull({this.anchorDay = 17});

  final int anchorDay;
}

/// Wraps an existing [ReportsPeriod] (This Month, Last Month, This Year,
/// Financial Year, …) so the Reports feature's period logic is reused as-is
/// rather than re-implemented for the dashboard.
class ReportsPeriodStrategy extends DateRangeStrategy {
  const ReportsPeriodStrategy(this.period);

  final ReportsPeriod period;
}

/// Rolling window of the last [days] days up to and including today.
class LastNDays extends DateRangeStrategy {
  const LastNDays(this.days);

  final int days;
}

/// A fixed, user-picked range that never moves with "today".
class CustomDateRange extends DateRangeStrategy {
  const CustomDateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

extension DateRangeStrategyX on DateRangeStrategy {
  /// Clamp an anchor day into a month, so day 31 in February resolves to the
  /// 28th/29th rather than overflowing into March.
  static DateTime _dayInMonth(int year, int month, int day) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > lastDayOfMonth ? lastDayOfMonth : day);
  }


  DateRange resolve(DateTime now, {int fiscalYearStartMonth = 1}) {
    switch (this) {
      case SalaryCycleToDate(:final anchorDay):
        final onOrAfterAnchor = now.day >= anchorDay;
        final startMonth = onOrAfterAnchor ? now.month : now.month - 1;
        final start = _dayInMonth(now.year, startMonth, anchorDay);
        return DateRange(start, now.dateOnly.add(const Duration(hours: 23, minutes: 59, seconds: 59)));

      case SalaryCycleFull(:final anchorDay):
        final onOrAfterAnchor = now.day >= anchorDay;
        final startMonth = onOrAfterAnchor ? now.month : now.month - 1;
        final start = _dayInMonth(now.year, startMonth, anchorDay);
        final end = _dayInMonth(start.year, start.month + 1, anchorDay);
        return DateRange(start, DateTime(end.year, end.month, end.day, 23, 59, 59));

      case ReportsPeriodStrategy(:final period):
        return period.rangeFor(now, fiscalYearStartMonth: fiscalYearStartMonth);

      case LastNDays(:final days):
        final start = now.dateOnly.subtract(Duration(days: days - 1));
        return DateRange(start, now.dateOnly.add(const Duration(hours: 23, minutes: 59, seconds: 59)));

      case CustomDateRange(:final start, :final end):
        return DateRange(start, end);
    }
  }

  String get label {
    switch (this) {
      case SalaryCycleToDate():
      case SalaryCycleFull():
        final range = resolve(DateTime.now());
        return 'Pay Period · ${range.start.shortDate} – ${range.end.shortDate}';
      case ReportsPeriodStrategy(:final period):
        return period.label;
      case LastNDays(:final days):
        return 'Last $days Days';
      case CustomDateRange():
        return 'Custom Range';
    }
  }
}
