/// Human label for a reminder offset (days before a due date) — shared by
/// every feature that schedules reminders via [ReminderNotificationService]
/// (Bills, EMI, ...), so the wording stays consistent across features
/// without each one reimplementing the same switch.
String reminderOffsetLabel(int offset) {
  switch (offset) {
    case 0:
      return 'Today';
    case 1:
      return 'Tomorrow';
    default:
      return '$offset days before';
  }
}
