import 'package:intl/intl.dart';

/// Date helpers used for grouping transactions and labeling sections
/// (e.g. "Today", "Yesterday") across history/report screens.
extension DateTimeX on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);

  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool get isToday => isSameDay(DateTime.now());

  bool get isYesterday =>
      isSameDay(DateTime.now().subtract(const Duration(days: 1)));

  bool isSameMonth(DateTime other) => year == other.year && month == other.month;

  /// Whether this date falls in the same calendar week (Monday-start,
  /// matching [startOfWeek]/[endOfWeek]) as [other].
  bool isSameWeek(DateTime other) => !dateOnly.isBefore(other.startOfWeek) && !dateOnly.isAfter(other.endOfWeek);

  DateTime get startOfMonth => DateTime(year, month, 1);

  DateTime get endOfMonth => DateTime(year, month + 1, 0, 23, 59, 59);

  DateTime get startOfWeek => subtract(Duration(days: weekday - 1)).dateOnly;

  DateTime get endOfWeek =>
      startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

  /// Human-friendly section label used in transaction history lists.
  String get sectionLabel {
    if (isToday) return 'Today';
    if (isYesterday) return 'Yesterday';
    if (isSameMonth(DateTime.now())) return DateFormat('d MMMM').format(this);
    return DateFormat('d MMMM yyyy').format(this);
  }

  String get shortDate => DateFormat('d MMM').format(this);
  String get fullDate => DateFormat('d MMM yyyy').format(this);
  String get monthYear => DateFormat('MMMM yyyy').format(this);
  String get dayOfWeek => DateFormat('EEEE').format(this);
}
