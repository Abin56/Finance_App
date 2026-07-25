import '../../../core/extensions/date_extensions.dart';
import '../../../core/utils/reminder_offset_label.dart';

/// Pure calculator over a set of reminder offsets and a due date — no
/// Firestore/Riverpod dependency, so it's trivial to unit test and to
/// drive notification scheduling from (see `ReminderNotificationService`).
/// Takes [dueDate]/[reminderOffsets] directly (an occurrence's due date, a
/// bill template's reminder settings) rather than a whole `Bill`, since
/// "due date" is now occurrence-scoped, not a template concern.
class BillReminder {
  BillReminder({required this.dueDate, required this.reminderOffsets, DateTime? now}) : _now = now ?? DateTime.now();

  final DateTime dueDate;
  final List<int> reminderOffsets;
  final DateTime _now;

  int get daysUntilDue => dueDate.dateOnly.difference(_now.dateOnly).inDays;

  /// Whether any configured offset matches today exactly — i.e. a
  /// reminder is due to fire today.
  bool get isDueToday => reminderOffsets.contains(daysUntilDue);

  /// Human label for a given offset value, matching the brief's fixed set
  /// (Today/Tomorrow/3 Days Before/7 Days Before) with a generic fallback
  /// for any other custom offset. Delegates to the shared
  /// [reminderOffsetLabel] so every feature's reminder wording stays
  /// consistent.
  static String labelForOffset(int offset) => reminderOffsetLabel(offset);

  /// Every offset that is due to fire today, with its label — a bill can
  /// have more than one offset land on the same day only if configured
  /// with duplicate values, which the form sheet prevents.
  List<String> get dueOffsetLabels =>
      reminderOffsets.where((offset) => offset == daysUntilDue).map(labelForOffset).toList();
}
