/// Deterministic, regex-based detection of "this SMS describes an upcoming
/// obligation, not a transaction that already happened" — the false
/// positive this exists to catch: a message like "₹8,500 will be debited
/// towards your EMI tomorrow" contains the keyword `debited`, which
/// `SmsRegexUtils.extractDirection` matches just as readily as a genuine
/// "₹8,500 debited" completed-transaction alert. Tense/futurity is the
/// actual distinguishing signal, and neither `SmsRegexUtils` nor any
/// `SmsParser` currently looks at it — this fills that gap as an
/// independent, always-on check `ReminderDetector`/`FinancialEventExtractor`
/// layer on top of, never a replacement for, the existing direction/amount
/// extraction.
abstract class ReminderSignals {
  ReminderSignals._();

  /// Explicit "this is a reminder" phrasing — the strongest signal, wins
  /// even if a past-tense completed-transaction verb also appears elsewhere
  /// in the same message (a reminder can legitimately reference what the
  /// past bill amount was).
  static final List<RegExp> _explicitReminderPatterns = [
    RegExp(r'\breminder\b', caseSensitive: false),
    RegExp(r'\bkindly pay\b', caseSensitive: false),
    RegExp(r'\bplease pay\b', caseSensitive: false),
    RegExp(r'\bplease make (the )?payment\b', caseSensitive: false),
    RegExp(r'\bpay (before|by)\b', caseSensitive: false),
    RegExp(r'\bdue date\b', caseSensitive: false),
    RegExp(r'\bpayment due\b', caseSensitive: false),
    RegExp(r'\bis due (on|tomorrow|today|this)\b', caseSensitive: false),
    RegExp(r'\bwill be due\b', caseSensitive: false),
    RegExp(
      r'\bupcoming (payment|due|bill|emi|installment)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bavoid late (fee|payment|charges)\b', caseSensitive: false),
    // Subscription/recurring-payment renewal notices (Phase 5 Part 8) — "Your
    // subscription will renew tomorrow" is an upcoming obligation, exactly
    // like a bill/EMI reminder, even though it never uses debit/credit
    // wording at all.
    RegExp(
      r'\b(subscription|membership) (will renew|renews?|renewal)\b',
      caseSensitive: false,
    ),
  ];

  /// Future-tense phrasing around a debit/payment verb — "will be debited",
  /// "is scheduled to be", "shall be deducted" — genuine completed-
  /// transaction alerts are always past tense ("was debited", "has been
  /// debited", or the bare past-tense verb alone: "debited").
  static final List<RegExp> _futureTensePatterns = [
    RegExp(
      r'\bwill be (debited|deducted|charged|auto[\s-]?debited)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bis scheduled to be\b', caseSensitive: false),
    RegExp(r'\bshall be (debited|deducted|charged)\b', caseSensitive: false),
    RegExp(r'\bwould be (debited|deducted|charged)\b', caseSensitive: false),
    RegExp(r'\bscheduled for\b', caseSensitive: false),
    RegExp(
      r'\bwill (renew|be renewed|auto[\s-]?renew)\b',
      caseSensitive: false,
    ),
  ];

  /// Explicit past-tense/completion markers that override a future-tense or
  /// reminder-shaped phrase elsewhere in the same message — a message that
  /// says both "was due" and "has now been paid" describes a completed
  /// transaction, not a reminder, so this check runs first in
  /// [looksLikeReminder].
  static final List<RegExp> _completionOverridePatterns = [
    RegExp(
      r'\bhas been (debited|credited|paid|received|processed)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bwas (debited|credited|paid|received)\b', caseSensitive: false),
    RegExp(
      r'\bpayment (of.{0,30})?(successful|received|processed)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bsuccessfully (paid|debited|credited|processed)\b',
      caseSensitive: false,
    ),
  ];

  /// Sentence boundary — splits on `.`/`!`/`?` followed by whitespace, or a
  /// newline. Deliberately simple (no abbreviation handling): the goal is
  /// only to separate independent clauses well enough to tell "this bill
  /// was paid" from "your next payment is due on 10 Sep" when they appear
  /// as two different sentences in the same SMS.
  static final RegExp _sentenceBoundary = RegExp(r'(?<=[.!?])\s+|\n+');

  /// True when [body] reads as a reminder/upcoming-obligation notice rather
  /// than an alert about money that has already moved.
  ///
  /// A completion marker (see [_completionOverridePatterns]) only overrides
  /// reminder-shaped wording *within the same sentence* — a genuinely
  /// completed payment must never be turned into a reminder just because
  /// reminder-like words appear elsewhere in the message, but a message that
  /// mentions a historical payment in one sentence ("...was paid last
  /// month.") and a real upcoming obligation in another ("Your next payment
  /// is due on 10 Sep.") is still a reminder about that upcoming obligation.
  /// If every sentence carrying reminder-shaped wording also carries a
  /// completion marker of its own, the message is not a reminder — the
  /// classic "your EMI was due yesterday and has now been paid" case.
  static bool looksLikeReminder(String body) {
    final sentences = body
        .split(_sentenceBoundary)
        .where((s) => s.trim().isNotEmpty);

    for (final sentence in sentences) {
      final isCompletionSentence = _completionOverridePatterns.any(
        (p) => p.hasMatch(sentence),
      );
      final isReminderShaped =
          _explicitReminderPatterns.any((p) => p.hasMatch(sentence)) ||
          _futureTensePatterns.any((p) => p.hasMatch(sentence));
      if (isReminderShaped && !isCompletionSentence) return true;
    }

    return false;
  }
}
