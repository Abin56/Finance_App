/// Human label for a reminder offset (days before a due date; negative means
/// days after, i.e. overdue) — shared by every feature that schedules
/// reminders via [ReminderNotificationService] (Bills, EMI, Loans...), so
/// the wording stays consistent across features without each one
/// reimplementing the same switch.
String reminderOffsetLabel(int offset) {
  switch (offset) {
    case 0:
      return 'Today';
    case 1:
      return 'Tomorrow';
    case < 0:
      final daysOverdue = -offset;
      return daysOverdue == 1 ? '1 day overdue' : '$daysOverdue days overdue';
    default:
      return '$offset days before';
  }
}
