import '../../extensions/date_extensions.dart';

/// One cycle's window — `[start, end]` inclusive, day-truncated comparison.
/// Structurally mirrors `StatementPeriod` (credit_cards feature) — promoted
/// here so any `core/payment_schedule` consumer can share the same window
/// shape without depending on the credit_cards feature layer.
class CyclePeriod {
  const CyclePeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final day = date.dateOnly;
    return !day.isBefore(start.dateOnly) && !day.isAfter(end.dateOnly);
  }
}
