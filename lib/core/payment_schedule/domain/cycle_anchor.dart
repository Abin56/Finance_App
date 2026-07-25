import '../../extensions/date_extensions.dart';
import 'cycle_period.dart';

/// Which cycle (relative to "now") a date falls into, per [CycleAnchor].
enum CycleClassification { previous, current, future }

/// A recurring monthly cycle boundary defined by a single anchor day of
/// month (default 17th). Mirrors how credit card statement cycles are
/// already derived from `CreditCardProfile.statementDay` (see
/// `StatementPeriodCalculator`), generalized so any feature can supply its
/// own anchor day (a card's statement day, a bill's due day, a loan's
/// installment day) without re-deriving month-clamping logic itself. Pure
/// value type; no I/O, no stored state.
class CycleAnchor {
  const CycleAnchor({this.anchorDay = 17});

  /// Day-of-month (1-31) the cycle boundary falls on; clamped to the
  /// shortest month the same way a statement/due day clamps (e.g. 31 -> 28/29
  /// in February).
  final int anchorDay;

  static DateTime _dayInMonth(int year, int month, int day) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final clampedDay = day > lastDayOfMonth ? lastDayOfMonth : day;
    return DateTime(year, month, clampedDay);
  }

  static DateTime _addMonths(DateTime date, int months) {
    final targetMonthIndex = date.month - 1 + months;
    final targetYear = date.year + targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    return _dayInMonth(targetYear, targetMonth, date.day);
  }

  /// The [CyclePeriod] whose window contains [now] (defaults to
  /// [DateTime.now]) — i.e. the currently in-progress, not-yet-closed cycle.
  /// The window is the anchor day exclusive of the previous month's anchor
  /// day through this month's anchor day, matching the "17 Jul -> 17 Aug"
  /// example: end is on-or-after [now], start is the day after the prior
  /// cycle's end.
  CyclePeriod currentCycleFor({DateTime? now}) {
    final today = (now ?? DateTime.now()).dateOnly;
    var end = _dayInMonth(today.year, today.month, anchorDay);
    if (end.isBefore(today)) {
      end = _addMonths(end, 1);
    }
    final start = _addMonths(end, -1).add(const Duration(days: 1));
    return CyclePeriod(start: start, end: end);
  }

  /// The [CyclePeriod] immediately before [currentCycleFor] — "the previous
  /// cycle", used to find previous-cycle-pending items.
  CyclePeriod previousCycleFor({DateTime? now}) {
    final current = currentCycleFor(now: now);
    final end = _addMonths(current.end, -1);
    final start = _addMonths(end, -1).add(const Duration(days: 1));
    return CyclePeriod(start: start, end: end);
  }

  /// Classifies [date] as [CycleClassification.previous]/[.current]/[.future]
  /// relative to [now] (defaults to [DateTime.now]), using this anchor's
  /// month boundaries. This is the one place "which cycle is this date in"
  /// is decided — every feature classifies through this method rather than
  /// comparing dates to its own cycle boundaries independently.
  CycleClassification classify(DateTime date, {DateTime? now}) {
    final current = currentCycleFor(now: now);
    if (current.contains(date)) return CycleClassification.current;
    if (date.dateOnly.isBefore(current.start)) return CycleClassification.previous;
    return CycleClassification.future;
  }
}
