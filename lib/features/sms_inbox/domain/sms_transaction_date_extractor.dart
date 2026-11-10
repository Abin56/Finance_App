import 'sms_event_class.dart';

/// The transaction date stated in the message body, when it can be read
/// reliably — otherwise the time the message was received.
class SmsTransactionDate {
  const SmsTransactionDate(this.dateTime, this.source);

  final DateTime dateTime;
  final SmsDateSource source;
}

/// Reads "on 01Nov26", "01-Nov-26", "1 Nov 2026", "15-07-26", "15/07/2026",
/// "2026-07-15" from a bank SMS. Indian banks write day-first, so `07/08`
/// is always 7 August, never July 8.
///
/// Reliability rules (any failure → the received time is used instead):
///  - a date written right after "on " wins; otherwise the body must
///    contain exactly ONE distinct date (a purchase SMS that also mentions
///    "due by 15 Nov" is ambiguous, so it is not guessed);
///  - the date must be real (no 31 Feb) and fall between 45 days before and
///    1 day after the message was received (a typo, a statement period or
///    a due date far away is not the transaction date).
///
/// When the body date is the received day, the received timestamp is kept
/// (it carries the time of day). Otherwise the body date is used at 12:00
/// local time — the SMS states no time, and midday keeps the calendar day
/// stable for a viewer in a nearby time zone.
abstract class SmsTransactionDateExtractor {
  SmsTransactionDateExtractor._();

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static final RegExp _dayMonthName = RegExp(
    r"(?<![\d])(\d{1,2})[-/ ]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?[-/ ,]*'?(\d{4}|\d{2})(?![\d])",
    caseSensitive: false,
  );
  static final RegExp _dayMonthNumeric = RegExp(
    r'(?<![\d.,/-])(\d{1,2})([-/.])(\d{1,2})\2(\d{4}|\d{2})(?![\d])',
  );
  static final RegExp _iso = RegExp(
    r'(?<![\d])(\d{4})-(\d{2})-(\d{2})(?![\d])',
  );

  static const Duration _maxPast = Duration(days: 45);
  static const Duration _maxFuture = Duration(days: 1);

  static SmsTransactionDate extract(String body, DateTime receivedAt) {
    final found = <({DateTime date, bool afterOn})>[];

    void add(int start, int y, int m, int d) {
      final year = y < 100 ? 2000 + y : y;
      if (m < 1 || m > 12 || d < 1 || d > 31) return;
      final date = DateTime(year, m, d);
      // Rejects 31 Feb etc. (DateTime rolls them over).
      if (date.month != m || date.day != d) return;
      final before = body.substring((start - 4).clamp(0, start), start);
      found.add((
        date: date,
        afterOn: RegExp(r'\bon\s*$', caseSensitive: false).hasMatch(before),
      ));
    }

    for (final m in _dayMonthName.allMatches(body)) {
      add(
        m.start,
        int.parse(m.group(3)!),
        _months[m.group(2)!.toLowerCase()]!,
        int.parse(m.group(1)!),
      );
    }
    for (final m in _dayMonthNumeric.allMatches(body)) {
      add(
        m.start,
        int.parse(m.group(4)!),
        int.parse(m.group(3)!),
        int.parse(m.group(1)!),
      );
    }
    for (final m in _iso.allMatches(body)) {
      add(
        m.start,
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }

    final fallback = SmsTransactionDate(
      receivedAt,
      SmsDateSource.messageReceived,
    );
    if (found.isEmpty) return fallback;

    DateTime? chosen;
    final afterOn = found.where((f) => f.afterOn).toList();
    if (afterOn.isNotEmpty) {
      chosen = afterOn.first.date;
    } else {
      final distinct = found.map((f) => f.date).toSet();
      if (distinct.length == 1) chosen = distinct.single;
    }
    if (chosen == null) return fallback;

    final receivedDay = DateTime(
      receivedAt.year,
      receivedAt.month,
      receivedAt.day,
    );
    if (chosen.isBefore(receivedDay.subtract(_maxPast)) ||
        chosen.isAfter(receivedDay.add(_maxFuture))) {
      return fallback;
    }
    if (chosen == receivedDay) {
      return SmsTransactionDate(receivedAt, SmsDateSource.messageBody);
    }
    return SmsTransactionDate(
      DateTime(chosen.year, chosen.month, chosen.day, 12),
      SmsDateSource.messageBody,
    );
  }
}
