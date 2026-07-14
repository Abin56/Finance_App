/// How a [PaymentSchedule]'s installments repeat. Mirrors
/// `BillRecurrence`'s date-math shape, kept as a separate enum since
/// `lib/core/` must not depend on `lib/features/bills/`.
enum ScheduleType { oneTime, weekly, monthly, custom }

extension ScheduleTypeX on ScheduleType {
  static ScheduleType fromName(String name) =>
      ScheduleType.values.firstWhere((t) => t.name == name, orElse: () => ScheduleType.oneTime);

  String get label {
    switch (this) {
      case ScheduleType.oneTime:
        return 'One time';
      case ScheduleType.weekly:
        return 'Weekly';
      case ScheduleType.monthly:
        return 'Monthly';
      case ScheduleType.custom:
        return 'Custom';
    }
  }

  /// Computes the next installment's due date from [current]. [customDays]
  /// is required (and only meaningful) for [custom]. Month addition clamps
  /// to the target month's last valid day (e.g. Jan 31 monthly -> Feb 28/29,
  /// never rolls into March) — same rule as `BillRecurrence.nextDueDate`.
  DateTime nextDueDate(DateTime current, {int? customDays}) {
    switch (this) {
      case ScheduleType.oneTime:
        return current;
      case ScheduleType.weekly:
        return current.add(const Duration(days: 7));
      case ScheduleType.monthly:
        return _addMonths(current, 1);
      case ScheduleType.custom:
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
