/// How often a [Bill] repeats. [oneTime] bills never roll over once paid;
/// every other value advances [Bill.dueDate] to its next occurrence when
/// the current one is paid or skipped — see [BillRepository]'s rollover
/// logic, the single place that owns this advancement.
enum BillRecurrence { oneTime, daily, weekly, monthly, yearly, custom }

extension BillRecurrenceX on BillRecurrence {
  static BillRecurrence fromName(String name) => BillRecurrence.values.firstWhere(
    (r) => r.name == name,
    orElse: () => BillRecurrence.oneTime,
  );

  String get label {
    switch (this) {
      case BillRecurrence.oneTime:
        return 'One time';
      case BillRecurrence.daily:
        return 'Daily';
      case BillRecurrence.weekly:
        return 'Weekly';
      case BillRecurrence.monthly:
        return 'Monthly';
      case BillRecurrence.yearly:
        return 'Yearly';
      case BillRecurrence.custom:
        return 'Custom';
    }
  }

  /// Computes the next occurrence's due date from [current]. [customDays]
  /// is required (and only meaningful) for [custom] — every other case
  /// ignores it. Month/year addition clamps to the target month's last
  /// valid day (e.g. Jan 31 monthly -> Feb 28/29, never rolls into March).
  DateTime nextDueDate(DateTime current, {int? customDays}) {
    switch (this) {
      case BillRecurrence.oneTime:
        return current;
      case BillRecurrence.daily:
        return current.add(const Duration(days: 1));
      case BillRecurrence.weekly:
        return current.add(const Duration(days: 7));
      case BillRecurrence.monthly:
        return _addMonths(current, 1);
      case BillRecurrence.yearly:
        return _addMonths(current, 12);
      case BillRecurrence.custom:
        return current.add(Duration(days: customDays ?? 1));
    }
  }

  static DateTime _addMonths(DateTime date, int months) {
    final targetMonthIndex = date.month - 1 + months;
    final targetYear = date.year + targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final lastDayOfTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    final targetDay = date.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : date.day;
    return DateTime(targetYear, targetMonth, targetDay, date.hour, date.minute, date.second);
  }
}
