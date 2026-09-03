/// Masks any run of 5+ digits down to its trailing 4 before an SMS body is
/// sent to the Cloud Function — full account numbers, card numbers, and
/// phone numbers embedded in a message (support lines, promo text) never
/// leave the device; only the last-4 style fragment the AI needs to reason
/// about phrasing survives. A bare 4-digit run (the masked-account style
/// `xxxx1234` already uses) is left untouched — it's already exactly what a
/// last-4 signal looks like and carries no more identity than that.
///
/// Currency amounts are explicitly protected from this masking. A comma-
/// grouped amount ("50,000") is naturally safe — the commas already break it
/// into runs shorter than 5 digits — but an unformatted one ("Rs 50000
/// debited", or SBI's "debited by 20000" phrasing with no currency symbol at
/// all) is a bare 5-digit run indistinguishable from an account number to
/// [_longDigitRun] alone, and masking it to "0000" would destroy the actual
/// transacted amount before the AI ever sees it — the single worst outcome
/// this redaction step could cause, since the AI's amount reconciliation
/// exists specifically to cross-check the regex-extracted amount.
abstract class SmsBodyRedactor {
  SmsBodyRedactor._();

  static final RegExp _longDigitRun = RegExp(r'\d{5,}');

  /// Mirrors `SmsRegexUtils`'s two amount patterns (currency-symbol-led, and
  /// SBI's symbol-less "debited/credited by N" phrasing) — kept as a
  /// separate, deliberately narrow pair here rather than importing that
  /// class, since this only needs to *locate* an amount span to protect it,
  /// not parse its value.
  static final RegExp _currencyAmountToken = RegExp(
    r'(?:rs|inr|₹)\s?\.?\s?[\d,]+(?:\.\d{1,2})?',
    caseSensitive: false,
  );

  static final RegExp _bareAmountToken = RegExp(
    r'\b(?:debited|credited)\s+by\s+[\d,]+(?:\.\d{1,2})?',
    caseSensitive: false,
  );

  static String redact(String body) {
    final protectedSpans = [
      ..._currencyAmountToken.allMatches(body).map((m) => (m.start, m.end)),
      ..._bareAmountToken.allMatches(body).map((m) => (m.start, m.end)),
    ];

    return body.replaceAllMapped(_longDigitRun, (match) {
      final overlapsAmount = protectedSpans.any(
        (span) => match.start < span.$2 && match.end > span.$1,
      );
      if (overlapsAmount) return match.group(0)!;

      final digits = match.group(0)!;
      return digits.substring(digits.length - 4);
    });
  }
}
