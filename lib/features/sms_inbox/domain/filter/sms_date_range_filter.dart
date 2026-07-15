/// Quick date presets for the inbox filter, plus [custom] which defers to a
/// user-picked range. Resolved to a concrete window by [resolve] so the
/// matching code never re-derives "what does This Month mean" per item.
enum SmsDatePreset { any, today, yesterday, last7Days, thisMonth, lastMonth, thisYear, custom }

/// A half-open window `[start, end)`. Half-open avoids the classic
/// end-of-day bug: an inclusive `end` at midnight silently drops every
/// message sent later that same day.
class SmsDateWindow {
  const SmsDateWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime moment) => !moment.isBefore(start) && moment.isBefore(end);
}

extension SmsDatePresetX on SmsDatePreset {
  String get label {
    switch (this) {
      case SmsDatePreset.any:
        return 'Any time';
      case SmsDatePreset.today:
        return 'Today';
      case SmsDatePreset.yesterday:
        return 'Yesterday';
      case SmsDatePreset.last7Days:
        return 'Last 7 days';
      case SmsDatePreset.thisMonth:
        return 'This month';
      case SmsDatePreset.lastMonth:
        return 'Last month';
      case SmsDatePreset.thisYear:
        return 'This year';
      case SmsDatePreset.custom:
        return 'Custom range';
    }
  }

  /// [customStart]/[customEnd] are only read for [SmsDatePreset.custom]; both
  /// are day-granular dates, and [customEnd] is treated as inclusive of its
  /// whole day, which is what a user picking "to 5 March" means.
  SmsDateWindow? resolve(DateTime now, {DateTime? customStart, DateTime? customEnd}) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case SmsDatePreset.any:
        return null;
      case SmsDatePreset.today:
        return SmsDateWindow(today, today.add(const Duration(days: 1)));
      case SmsDatePreset.yesterday:
        return SmsDateWindow(today.subtract(const Duration(days: 1)), today);
      case SmsDatePreset.last7Days:
        // Includes today, so the window spans 7 calendar days, not 8.
        return SmsDateWindow(today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1)));
      case SmsDatePreset.thisMonth:
        return SmsDateWindow(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case SmsDatePreset.lastMonth:
        return SmsDateWindow(DateTime(now.year, now.month - 1), DateTime(now.year, now.month));
      case SmsDatePreset.thisYear:
        return SmsDateWindow(DateTime(now.year), DateTime(now.year + 1));
      case SmsDatePreset.custom:
        if (customStart == null || customEnd == null) return null;
        final start = DateTime(customStart.year, customStart.month, customStart.day);
        final end = DateTime(customEnd.year, customEnd.month, customEnd.day).add(const Duration(days: 1));
        return SmsDateWindow(start, end);
    }
  }
}
