/// A date found in OCR text. [hasExplicitYear] is false when the year had to
/// be inferred (e.g. "05 Sep" with no year printed anywhere) — the review
/// screen still shows the resulting date as a normal, editable value, but
/// callers that want to be conservative about trusting an inferred year can
/// check this flag.
class ParsedDate {
  const ParsedDate({
    required this.date,
    required this.hasExplicitYear,
    required this.rawText,
  });

  final DateTime date;
  final bool hasExplicitYear;
  final String rawText;
}

/// Parses the handful of date shapes that actually show up in bank/UPI/
/// wallet screenshots: "05 Sep", "Sep 05", "05 Sep 2026", "05/09/2026",
/// "05-09-26". Never invents a date it can't support — an unparseable string
/// returns null so the caller can flag that row for review instead of
/// silently attaching a wrong date.
abstract class SmartImportDateParser {
  SmartImportDateParser._();

  static const Map<String, int> _monthNames = {
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'sept': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };

  // "05 Sep", "05 Sep 2026", "05 Sep, 2026", "05-Sep-26", "05.Sep.2026" — bank
  // SMS/app alerts (HDFC, ICICI and others) routinely hyphen- or dot-join a
  // day and month name instead of separating them with a space, so the
  // day/month separator accepts space, hyphen or dot, not just whitespace.
  // The trailing year group only accepts exactly 2 or 4 digits (never 1 or
  // 3): a real year is always written one of those two ways, so without this
  // restriction a plain amount sitting right after the date on the same line
  // ("06 Sep 420 DR") gets misread as a 3-digit year, producing a nonsense
  // date like "0420". The separator before the year is similarly widened to
  // accept a hyphen ("05-Sep-26") alongside the existing comma/whitespace.
  static final RegExp _dayMonthYearPattern = RegExp(
    r'\b(\d{1,2})[\s\-.]+([A-Za-z]{3,9})\.?[,\-]?\s*(\d{2}|\d{4})?\b',
  );

  // "Sep 05", "Sep 05th", "Sep 05, 2026", "Sep-05-2026" — same separator and
  // 2-or-4-digit year rules as above, for the same reasons.
  static final RegExp _monthDayYearPattern = RegExp(
    r'\b([A-Za-z]{3,9})\.?[\s\-.]+(\d{1,2})(?:st|nd|rd|th)?[,\-]?\s*(\d{2}|\d{4})?\b',
  );

  // "05/09/2026", "05-09-26", "05.09.2026"
  static final RegExp _numericPattern = RegExp(
    r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})\b',
  );

  // "2026-09-05" — ISO 8601's year-first order is unambiguous (a 4-digit
  // leading group can only be a year), so it's checked ahead of the
  // day/month-first numeric pattern above rather than folded into it.
  static final RegExp _isoPattern = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');

  /// [referenceDate] anchors "what year is this probably" when the text has
  /// no year — defaults to now, but callers can pass the screenshot's own
  /// context date (e.g. a statement period) when one is known.
  static ParsedDate? tryParse(String text, {DateTime? referenceDate}) {
    final reference = referenceDate ?? DateTime.now();

    for (final match in _dayMonthYearPattern.allMatches(text)) {
      final day = int.tryParse(match.group(1)!);
      final month = _monthNames[match.group(2)!.toLowerCase()];
      if (day == null || month == null) continue;
      final parsed = _build(
        day: day,
        month: month,
        yearText: match.group(3),
        rawText: match.group(0)!,
        reference: reference,
      );
      if (parsed != null) return parsed;
    }

    for (final match in _monthDayYearPattern.allMatches(text)) {
      final month = _monthNames[match.group(1)!.toLowerCase()];
      final day = int.tryParse(match.group(2)!);
      if (day == null || month == null) continue;
      final parsed = _build(
        day: day,
        month: month,
        yearText: match.group(3),
        rawText: match.group(0)!,
        reference: reference,
      );
      if (parsed != null) return parsed;
    }

    final isoMatch = _isoPattern.firstMatch(text);
    if (isoMatch != null) {
      final year = int.tryParse(isoMatch.group(1)!);
      final month = int.tryParse(isoMatch.group(2)!);
      final day = int.tryParse(isoMatch.group(3)!);
      if (year != null && month != null && day != null) {
        final parsed = _build(
          day: day,
          month: month,
          yearText: isoMatch.group(1),
          rawText: isoMatch.group(0)!,
          reference: reference,
        );
        if (parsed != null) return parsed;
      }
    }

    final numericMatch = _numericPattern.firstMatch(text);
    if (numericMatch != null) {
      final first = int.tryParse(numericMatch.group(1)!);
      final second = int.tryParse(numericMatch.group(2)!);
      final yearText = numericMatch.group(3)!;
      if (first != null && second != null) {
        // Indian screenshots are overwhelmingly day-first; only flip to
        // month-first when the first number can't possibly be a day (i.e.
        // it's within month range while the second number isn't).
        final monthFirst = first <= 12 && second > 12;
        final day = monthFirst ? second : first;
        final month = monthFirst ? first : second;
        final parsed = _build(
          day: day,
          month: month,
          yearText: yearText,
          rawText: numericMatch.group(0)!,
          reference: reference,
        );
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  static ParsedDate? _build({
    required int day,
    required int month,
    required String? yearText,
    required String rawText,
    required DateTime reference,
  }) {
    if (month < 1 || month > 12) return null;
    final hasExplicitYear = yearText != null;
    final year = hasExplicitYear
        ? _resolveFullYear(yearText)
        : _inferYear(month: month, day: day, reference: reference);

    final daysInMonth = DateTime(year, month + 1, 0).day;
    if (day < 1 || day > daysInMonth) return null;

    return ParsedDate(
      date: DateTime(year, month, day),
      hasExplicitYear: hasExplicitYear,
      rawText: rawText,
    );
  }

  /// No year printed — assume the current year unless that would place the
  /// date more than a couple of days in the future (allowing a little slack
  /// for timezones), in which case the screenshot almost certainly predates
  /// a year boundary and the previous year is the sane guess.
  static int _inferYear({
    required int month,
    required int day,
    required DateTime reference,
  }) {
    final daysInMonth = DateTime(reference.year, month + 1, 0).day;
    if (day < 1 || day > daysInMonth) return reference.year;
    final candidate = DateTime(reference.year, month, day);
    if (candidate.isAfter(reference.add(const Duration(days: 2)))) {
      return reference.year - 1;
    }
    return reference.year;
  }

  static int _resolveFullYear(String yearText) {
    final parsed = int.tryParse(yearText) ?? 0;
    if (yearText.length > 2) return parsed;
    return parsed <= 79 ? 2000 + parsed : 1900 + parsed;
  }
}
