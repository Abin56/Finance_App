/// Which real-world date a [ResolvedObligationDate] represents — the whole
/// point of Part 3's date-semantics requirement: an obligation-shaped SMS
/// almost never means "the date this arrived," and conflating that with
/// the date money is actually due/scheduled is exactly the bug this engine
/// exists to prevent.
enum ObligationDateKind {
  /// An explicit due-date notice ("due on 5 Sep", "payment due tomorrow").
  dueDate,

  /// A future-tense scheduled debit ("will be debited on...", "scheduled
  /// for...").
  scheduledDebitDate,

  /// A reminder-only date with no due/scheduled framing ("reminder: pay on
  /// 5 Sep").
  reminderDate,

  /// An expiry/lapse date ("recharge before expiry on 5 Sep").
  expiryDate,

  /// A statement-generation date, distinct from the payment due date.
  statementDate,

  /// A deadline phrased as "by"/"before" rather than "due on".
  paymentDeadline,

  /// No date could be resolved — the honest default, never guessed at (see
  /// Safety rule 11: "Unknown date must remain unknown").
  unknown,
}

/// One date extracted from an obligation-shaped SMS, plus which kind of
/// date it is and how it was derived. [value] is `null` whenever nothing in
/// the message text could be resolved to a concrete date — this class
/// exists precisely so "unknown" stays representable, mirroring
/// `FieldConfidence.unknown()`'s role for other fields.
class ResolvedObligationDate {
  const ResolvedObligationDate({
    required this.value,
    required this.kind,
    required this.confidence,
    this.evidence,
  });

  const ResolvedObligationDate.unknown()
    : value = null,
      kind = ObligationDateKind.unknown,
      confidence = 0.0,
      evidence = null;

  final DateTime? value;
  final ObligationDateKind kind;

  /// 0.0-1.0.
  final double confidence;

  /// The matched substring backing [value], shown to a reviewer as an
  /// explanation — never fabricated.
  final String? evidence;

  bool get isKnown => value != null;
}

/// Deterministic, regex-based resolution of the date an obligation-shaped
/// SMS actually refers to — distinct from `RawSmsMessage.date` (when the
/// SMS was received), which this resolver never uses as a fallback for a
/// date it could not find (see Safety rule 11).
///
/// Intentionally narrow and hand-rolled (no date-parsing package in this
/// project, see the SMS AI rebuild plan's no-heavy-dependency posture) —
/// covers the relative/absolute phrasings enumerated in the Phase 4 task,
/// not general natural-language date parsing.
abstract class ObligationDateResolver {
  ObligationDateResolver._();

  static const _months = {
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

  static const _weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  /// Resolves the single most relevant date in [body], anchored at
  /// [referenceDate] (typically the SMS's own received timestamp — never
  /// `DateTime.now()`, so resolution stays reproducible in tests and
  /// unaffected by when the pipeline happens to run).
  static ResolvedObligationDate resolve(
    String body, {
    required DateTime referenceDate,
  }) {
    final lower = body.toLowerCase();

    final within = _matchWithinHours(lower, referenceDate);
    if (within != null) return within;

    final inDays = _matchInDays(lower, referenceDate);
    if (inDays != null) return inDays;

    final relativeDay = _matchRelativeDay(lower, referenceDate);
    if (relativeDay != null) return relativeDay;

    final nextWeekday = _matchNextWeekday(lower, referenceDate);
    if (nextWeekday != null) return nextWeekday;

    final absolute = _matchAbsoluteDate(lower, body, referenceDate);
    if (absolute != null) return absolute;

    return const ResolvedObligationDate.unknown();
  }

  static ObligationDateKind _kindFor(String context) {
    if (RegExp(
      r'\b(will be debited|scheduled for|scheduled to be|auto[\s-]?debit)\b',
    ).hasMatch(context)) {
      return ObligationDateKind.scheduledDebitDate;
    }
    if (RegExp(r'\b(expir|recharge)\w*\b').hasMatch(context)) {
      return ObligationDateKind.expiryDate;
    }
    if (RegExp(r'\bstatement\b').hasMatch(context)) {
      return ObligationDateKind.statementDate;
    }
    if (RegExp(r'\b(by|before|within)\b').hasMatch(context)) {
      return ObligationDateKind.paymentDeadline;
    }
    if (RegExp(r'\bdue\b').hasMatch(context)) {
      return ObligationDateKind.dueDate;
    }
    if (RegExp(r'\breminder\b').hasMatch(context)) {
      return ObligationDateKind.reminderDate;
    }
    return ObligationDateKind.dueDate;
  }

  static String _contextAround(String lower, Match m) {
    final start = (m.start - 25).clamp(0, lower.length);
    final end = (m.end + 10).clamp(0, lower.length);
    return lower.substring(start, end);
  }

  /// "within 48 hours" / "within 2 hours".
  static ResolvedObligationDate? _matchWithinHours(
    String lower,
    DateTime reference,
  ) {
    final m = RegExp(r'\bwithin\s+(\d{1,3})\s*hours?\b').firstMatch(lower);
    if (m == null) return null;
    final hours = int.parse(m.group(1)!);
    return ResolvedObligationDate(
      value: reference.add(Duration(hours: hours)),
      kind: ObligationDateKind.paymentDeadline,
      confidence: 0.8,
      evidence: m.group(0),
    );
  }

  /// "due in 3 days" / "in 2 days".
  static ResolvedObligationDate? _matchInDays(
    String lower,
    DateTime reference,
  ) {
    final m = RegExp(r'\bin\s+(\d{1,3})\s*days?\b').firstMatch(lower);
    if (m == null) return null;
    final days = int.parse(m.group(1)!);
    final context = _contextAround(lower, m);
    return ResolvedObligationDate(
      value: reference.add(Duration(days: days)),
      kind: _kindFor(context),
      confidence: 0.8,
      evidence: m.group(0),
    );
  }

  /// "today" / "tomorrow" / "day after tomorrow".
  static ResolvedObligationDate? _matchRelativeDay(
    String lower,
    DateTime reference,
  ) {
    final dayAfterTomorrow = RegExp(
      r'\bday after tomorrow\b',
    ).firstMatch(lower);
    if (dayAfterTomorrow != null) {
      final context = _contextAround(lower, dayAfterTomorrow);
      return ResolvedObligationDate(
        value: reference.add(const Duration(days: 2)),
        kind: _kindFor(context),
        confidence: 0.85,
        evidence: dayAfterTomorrow.group(0),
      );
    }
    final tomorrow = RegExp(r'\btomorrow\b').firstMatch(lower);
    if (tomorrow != null) {
      final context = _contextAround(lower, tomorrow);
      return ResolvedObligationDate(
        value: reference.add(const Duration(days: 1)),
        kind: _kindFor(context),
        confidence: 0.85,
        evidence: tomorrow.group(0),
      );
    }
    final today = RegExp(r'\btoday\b').firstMatch(lower);
    if (today != null) {
      final context = _contextAround(lower, today);
      return ResolvedObligationDate(
        value: DateTime(reference.year, reference.month, reference.day),
        kind: _kindFor(context),
        confidence: 0.85,
        evidence: today.group(0),
      );
    }
    return null;
  }

  /// "next Monday" — the next occurrence of that weekday strictly after
  /// [reference]'s own date (never today, even if today is that weekday).
  static ResolvedObligationDate? _matchNextWeekday(
    String lower,
    DateTime reference,
  ) {
    final m = RegExp(
      r'\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    ).firstMatch(lower);
    if (m == null) return null;
    final targetWeekday = _weekdays[m.group(1)!]!;
    var daysAhead = (targetWeekday - reference.weekday) % 7;
    if (daysAhead <= 0) daysAhead += 7;
    final context = _contextAround(lower, m);
    return ResolvedObligationDate(
      value: DateTime(
        reference.year,
        reference.month,
        reference.day,
      ).add(Duration(days: daysAhead)),
      kind: _kindFor(context),
      confidence: 0.8,
      evidence: m.group(0),
    );
  }

  /// "on 5th September" / "5 Sep" / "by 10 Sep 2026" — day + month name,
  /// with an optional ordinal suffix and optional year (defaults to
  /// [reference]'s year, rolled to next year only if that would place the
  /// date more than 300 days in the past — guards against a December SMS
  /// naming a January date without an explicit year).
  static ResolvedObligationDate? _matchAbsoluteDate(
    String lower,
    String original,
    DateTime reference,
  ) {
    final monthNames = _months.keys.join('|');
    final m = RegExp(
      '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+($monthNames)\\b(?:\\s+(\\d{4}))?',
    ).firstMatch(lower);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = _months[m.group(2)!]!;
    if (day < 1 || day > 31) return null;
    var year = m.group(3) != null ? int.parse(m.group(3)!) : reference.year;
    var candidate = DateTime(year, month, day);
    if (m.group(3) == null &&
        candidate.isBefore(reference.subtract(const Duration(days: 300)))) {
      year += 1;
      candidate = DateTime(year, month, day);
    }
    final context = _contextAround(lower, m);
    return ResolvedObligationDate(
      value: candidate,
      kind: _kindFor(context),
      confidence: 0.85,
      evidence: m.group(0),
    );
  }
}
