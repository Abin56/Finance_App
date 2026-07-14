import 'credit_card_profile.dart';

/// One statement cycle's window and due date — `[periodStart, periodEnd]`
/// inclusive, `dueDate` the day payment is due. Pure value type, never
/// persisted on its own (see `Statement`, which stores a materialized
/// cycle's totals once it's closed).
class StatementPeriod {
  const StatementPeriod({required this.periodStart, required this.periodEnd, required this.dueDate});

  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime dueDate;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final end = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

/// Pure functions computing a [CreditCardProfile]'s statement cycles from
/// its `statementDay`/`paymentDueDay` — no I/O, no stored state. Mirrors
/// `BillRecurrence.nextDueDate`'s month-clamping (a statement/due day of 31
/// clamps to the shorter month's last day, e.g. 31 -> 28/29 in February)
/// rather than reusing that method directly, since a statement cycle is a
/// window between two clamped dates, not a single rolling due date.
abstract class StatementPeriodCalculator {
  StatementPeriodCalculator._();

  /// The statement-day date that falls in [year]/[month], clamped to that
  /// month's last valid day.
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

  /// The cycle whose `periodEnd` (statement date) is on or after [now] —
  /// i.e. the currently in-progress (not yet closed) cycle. [now] defaults
  /// to [DateTime.now] when omitted.
  static StatementPeriod currentCycleFor(CreditCardProfile card, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var periodEnd = _dayInMonth(today.year, today.month, card.statementDay);
    if (periodEnd.isBefore(DateTime(today.year, today.month, today.day))) {
      periodEnd = _addMonths(periodEnd, 1);
    }
    return _periodEnding(card, periodEnd);
  }

  /// The most recently *closed* cycle as of [now] — the one a `Statement`
  /// should be materialized for once nothing has been generated yet.
  static StatementPeriod mostRecentClosedCycleFor(CreditCardProfile card, {DateTime? now}) {
    final current = currentCycleFor(card, now: now);
    final today = DateTime(
      (now ?? DateTime.now()).year,
      (now ?? DateTime.now()).month,
      (now ?? DateTime.now()).day,
    );
    if (current.periodEnd.isBefore(today) || current.periodEnd.isAtSameMomentAs(today)) {
      return current;
    }
    return _periodEnding(card, _addMonths(current.periodEnd, -1));
  }

  static StatementPeriod _periodEnding(CreditCardProfile card, DateTime periodEnd) {
    final periodStart = _addMonths(periodEnd, -1).add(const Duration(days: 1));
    final dueMonth = _addMonths(periodEnd, 1);
    final dueDate = _dayInMonth(dueMonth.year, dueMonth.month, card.paymentDueDay);
    return StatementPeriod(periodStart: periodStart, periodEnd: periodEnd, dueDate: dueDate);
  }
}
