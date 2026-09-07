/// One amount found in OCR text, plus whether it carried an explicit
/// currency marker (₹/Rs/INR) — a currency-marked match is trusted far more
/// than a bare number, since a bare number is just as likely to be a date,
/// a masked account digit group, or a reference number. [isBalanceOnly]
/// means every candidate amount in the text was immediately preceded by
/// balance wording ("Avl Bal", "Closing Balance", …) — callers should treat
/// this as "no reliable transaction amount" rather than use it, since a
/// balance figure is not a transaction.
class ParsedAmount {
  const ParsedAmount({
    required this.value,
    required this.rawText,
    required this.hadCurrencyMarker,
    this.isBalanceOnly = false,
  });

  final double value;
  final String rawText;
  final bool hadCurrencyMarker;
  final bool isBalanceOnly;
}

/// Extracts a monetary amount from OCR'd screenshot text.
///
/// Screenshots come from every kind of banking/UPI/wallet app, so this never
/// assumes a fixed layout — it looks for a currency-marked figure first
/// (₹420, Rs.1,299, INR 185.50) and only falls back to a bare decimal number
/// (420.00) when no currency marker is present anywhere in the text. A bare
/// integer with no decimal point is never treated as an amount on its own —
/// that pattern is exactly as likely to be a date's day-of-month or a masked
/// account/card digit group, and guessing wrong there is worse than leaving
/// the amount unset and flagging the row for review.
abstract class SmartImportAmountParser {
  SmartImportAmountParser._();

  static final RegExp _currencyMarkedPattern = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9oOiIlLsS]+(?:[,.][0-9oOiIlLsS]+)*)',
    caseSensitive: false,
  );

  // A bare number is only trusted as an amount when it has a two-digit
  // decimal tail (₹-style paise) — that's the one shape a date or account
  // fragment never takes.
  static final RegExp _bareDecimalPattern = RegExp(
    r'\b([0-9oOiIlLsS]{1,3}(?:,[0-9oOiIlLsS]{2,3})*\.[0-9oOiIlLsS]{2}|[0-9oOiIlLsS]+\.[0-9oOiIlLsS]{2})\b',
  );

  // A screenshot routinely states a balance figure (opening/closing/
  // available) alongside the actual transaction amount — an amount
  // immediately preceded by one of these must never be preferred over a
  // genuine transaction amount elsewhere in the same text, and if it's the
  // *only* candidate, it must not be used at all (see [ParsedAmount.isBalanceOnly]).
  static final RegExp _balanceContextPattern = RegExp(
    r'\b(avl\.?\s*bal|available\s*bal(?:ance)?|opening\s*bal(?:ance)?|closing\s*bal(?:ance)?|current\s*bal(?:ance)?|bal(?:ance)?)\b',
    caseSensitive: false,
  );

  static const Set<String> _confusableLetters = {
    'o',
    'O',
    'i',
    'I',
    'l',
    'L',
    's',
    'S',
  };

  /// Returns the best plausible amount in [text]: a currency-marked figure
  /// if one exists (preferring one that isn't balance-adjacent), otherwise
  /// the best bare decimal figure.
  static ParsedAmount? extractFirst(String text) {
    return _bestMatch(text, _currencyMarkedPattern, hadCurrencyMarker: true) ??
        _bestMatch(text, _bareDecimalPattern, hadCurrencyMarker: false);
  }

  static ParsedAmount? _bestMatch(
    String text,
    RegExp pattern, {
    required bool hadCurrencyMarker,
  }) {
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return null;

    // Same lookback-window logic as SMS Inbox's own `SmsRegexUtils` — a
    // match is "balance-adjacent" only if balance wording appears in the
    // (previous-match-clamped) 20 characters right before it, so an earlier
    // match's own balance prefix can't bleed forward and wrongly flag a
    // later, unrelated amount.
    final nonBalance = <RegExpMatch>[];
    final balanceAdjacent = <RegExpMatch>[];
    var previousEnd = 0;
    for (final match in matches) {
      final rawWindowStart = match.start - 20;
      final windowStart =
          (rawWindowStart > previousEnd ? rawWindowStart : previousEnd).clamp(
            0,
            text.length,
          );
      final context = text.substring(windowStart, match.start);
      (_balanceContextPattern.hasMatch(context) ? balanceAdjacent : nonBalance)
          .add(match);
      previousEnd = match.end;
    }

    for (final match in nonBalance) {
      final parsed = _tryBuild(
        match,
        text,
        hadCurrencyMarker: hadCurrencyMarker,
        isBalanceOnly: false,
      );
      if (parsed != null) return parsed;
    }
    // Every candidate was balance-adjacent — still surfaced (flagged via
    // [ParsedAmount.isBalanceOnly]) rather than dropped silently, so a
    // caller can decide not to treat it as a real transaction amount.
    for (final match in balanceAdjacent) {
      final parsed = _tryBuild(
        match,
        text,
        hadCurrencyMarker: hadCurrencyMarker,
        isBalanceOnly: true,
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  static ParsedAmount? _tryBuild(
    RegExpMatch match,
    String text, {
    required bool hadCurrencyMarker,
    required bool isBalanceOnly,
  }) {
    final rawDigits = match.group(1)!;
    final trimmedDigits = _stripWordBleed(rawDigits, text, match.end);
    if (trimmedDigits.isEmpty) return null;

    final value = _normalize(trimmedDigits);
    if (value == null) return null;

    final trimmedChars = rawDigits.length - trimmedDigits.length;
    final rawText = match
        .group(0)!
        .substring(0, match.group(0)!.length - trimmedChars);
    return ParsedAmount(
      value: value,
      rawText: rawText,
      hadCurrencyMarker: hadCurrencyMarker,
      isBalanceOnly: isBalanceOnly,
    );
  }

  /// A greedy OCR-tolerant digit run can swallow the first letter(s) of an
  /// immediately-following word when there's no space between an amount and
  /// the next text — e.g. "₹420SWIGGY": the digit pattern's OCR-confusable
  /// character class (o/O/i/I/l/L/s/S, tolerated because OCR often misreads
  /// a real "0"/"1"/"5" as one of these) would otherwise consume the "S" of
  /// SWIGGY as part of the number, producing 4205 instead of 420 and
  /// mangling the merchant name into "WIGGY". A trailing confusable letter
  /// is only trusted as a digit when nothing alphabetic immediately follows
  /// it in the source text (e.g. the trailing "S" in "₹1,29S" at the end of
  /// a line/string, a genuine OCR misread with nothing to bleed into).
  static String _stripWordBleed(
    String rawDigits,
    String fullText,
    int matchEnd,
  ) {
    if (matchEnd >= fullText.length ||
        !RegExp(r'[A-Za-z]').hasMatch(fullText[matchEnd])) {
      return rawDigits;
    }
    var trimmed = rawDigits;
    while (trimmed.isNotEmpty &&
        _confusableLetters.contains(trimmed[trimmed.length - 1])) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Cleans up a captured numeric token and parses it safely, correcting the
  /// OCR digit/letter confusions the token pattern deliberately tolerates
  /// (O/o→0, I/i/l/L→1, S/s→5) before stripping thousands separators.
  static double? _normalize(String rawToken) {
    var token = rawToken
        .replaceAll(RegExp('[oO]'), '0')
        .replaceAll(RegExp('[ilIL]'), '1')
        .replaceAll(RegExp('[sS]'), '5')
        .replaceAll(RegExp(r'\s'), '');

    if (token.isEmpty) return null;

    final lastComma = token.lastIndexOf(',');
    final lastDot = token.lastIndexOf('.');

    String normalized;
    if (lastComma == -1 && lastDot == -1) {
      normalized = token;
    } else if (lastDot > lastComma) {
      // '.' is the decimal separator (the common case) — unless there are
      // more than 2 digits after it, which means it's almost certainly an
      // OCR-mangled thousands separator instead of real paise.
      final fractionDigits = token.length - lastDot - 1;
      normalized = fractionDigits <= 2
          ? token.replaceAll(',', '')
          : token.replaceAll(RegExp('[,.]'), '');
    } else {
      // No decimal point after the last comma — both are grouping noise.
      normalized = token.replaceAll(RegExp('[,.]'), '');
    }

    final value = double.tryParse(normalized);
    if (value == null || value <= 0 || value > 100000000) return null;
    return value;
  }
}
