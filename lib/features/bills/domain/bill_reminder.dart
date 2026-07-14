import '../../../core/extensions/date_extensions.dart';
import '../../../core/utils/reminder_offset_label.dart';
import 'bill.dart';

/// Pure calculator over a [Bill]'s [Bill.reminderOffsets] and due date —
/// no Firestore/Riverpod dependency, so it's trivial to unit test and to
/// drive notification scheduling from (see `ReminderNotificationService`).
class BillReminder {
  BillReminder({required this.bill, DateTime? now}) : _now = now ?? DateTime.now();

  final Bill bill;
  final DateTime _now;

  int get daysUntilDue => bill.dueDate.dateOnly.difference(_now.dateOnly).inDays;

  /// Whether any configured offset matches today exactly — i.e. a
  /// reminder is due to fire today.
  bool get isDueToday => bill.reminderOffsets.contains(daysUntilDue);

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
      bill.reminderOffsets.where((offset) => offset == daysUntilDue).map(labelForOffset).toList();
}
