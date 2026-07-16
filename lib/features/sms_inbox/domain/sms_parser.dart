import 'parsed_sms_transaction.dart';
import 'raw_sms_message.dart';

/// One bank/format-specific (or generic-fallback) SMS parser. Implementations
/// live under `bank_parsers/` and are tried in order by `SmsParserRegistry`
/// — adding a new bank is a pure addition (a new file + one registry entry),
/// never a change to an existing parser.
abstract class SmsParser {
  const SmsParser();

  /// Whether this parser recognizes [message]'s sender/format well enough
  /// to attempt [parse]. Checked before [parse] is ever called.
  bool canParse(RawSmsMessage message);

  /// Extracts transaction fields from [message]. Only called after
  /// [canParse] returns true; may still return null if the body doesn't
  /// actually contain a recognizable amount/direction despite matching the
  /// sender pattern.
  ParsedSmsTransaction? parse(RawSmsMessage message);
}

/// Negative-list filter run before any [SmsParser] — messages that look
/// like OTPs, promotions, delivery updates, or recharge reminders are never
/// treated as financial, no matter how "bank-like" their sender looks.
abstract class SmsFinancialFilter {
  SmsFinancialFilter._();

  /// Unambiguous security-sensitive content — always rejected, even if the
  /// message also happens to contain a financial signal (e.g. an OTP
  /// message that quotes the amount it's securing). Never overridden.
  static final List<RegExp> _hardNonFinancialPatterns = [
    RegExp(r'\bOTP\b', caseSensitive: false),
    RegExp(r'one[\s-]?time password', caseSensitive: false),
    RegExp(r'do not share.{0,20}(otp|pin|cvv)', caseSensitive: false),
    RegExp(r'verification code', caseSensitive: false),
  ];

  /// Promotional/informational phrasing that *usually* means "not a
  /// transaction" but can appear inside a genuine transaction SMS's merchant
  /// name or free text (e.g. "spent at Flipkart Big Billion Sale Store on
  /// your Debit Card"). Only applied when [_transactionVerbSignals] finds no
  /// actual transaction verb/rail — see [isFinancial] — so a real debit/
  /// credit alert is never silently discarded just because it mentions a
  /// sale/offer, but a promo that merely quotes an amount ("Rs.500 off")
  /// with no transaction verb is still correctly rejected.
  static final List<RegExp> _softNonFinancialPatterns = [
    RegExp(r'\brecharge\b', caseSensitive: false),
    RegExp(r'\b\d{1,3}%\s*off\b', caseSensitive: false),
    RegExp(r'\bcashback offer\b', caseSensitive: false),
    RegExp(r'\bsale\b.{0,20}\b(shop|buy|store)\b', caseSensitive: false),
    RegExp(r'\bhas been (dispatched|delivered|shipped|out for delivery)\b', caseSensitive: false),
    RegExp(r'\btrack (your|this) (order|package|shipment)\b', caseSensitive: false),
    RegExp(r'\bis now live\b', caseSensitive: false),
    RegExp(r'\bunsubscribe\b', caseSensitive: false),
    RegExp(r'\bapply now\b', caseSensitive: false),
    RegExp(r'\bwin\b.{0,20}\bprize\b', caseSensitive: false),
  ];

  /// Strong evidence an actual transaction happened — a completion verb or
  /// the rail it moved on. Deliberately narrower than [_financialSignals]:
  /// a bare amount ("Rs.500 off") isn't enough on its own to override the
  /// promotional filter above, since promo messages routinely quote amounts
  /// too.
  static final List<RegExp> _transactionVerbSignals = [
    RegExp(r'\b(debited|credited|withdrawn|spent|paid|received|deposited)\b', caseSensitive: false),
    RegExp(r'\bupi\b', caseSensitive: false),
    RegExp(r'\b(imps|neft|rtgs)\b', caseSensitive: false),
    RegExp(r'\bemi\b', caseSensitive: false),
  ];

  static final List<RegExp> _financialSignals = [
    ..._transactionVerbSignals,
    RegExp(r'(rs\.?|inr|₹)\s?[\d,]+(\.\d+)?', caseSensitive: false),
    RegExp(r'\b(a/c|acct|account|card)\b.{0,10}(x{2,}|\*{2,})?\d{3,4}', caseSensitive: false),
  ];

  /// True only for messages that look like a real bank/UPI transaction
  /// notification — never OTPs, promos, spam, delivery updates, or recharge
  /// reminders, even if they came from a bank-looking sender. A genuine
  /// transaction SMS is never silently dropped just because its merchant
  /// name or free text happens to contain promotional-sounding words — see
  /// [_softNonFinancialPatterns].
  static bool isFinancial(RawSmsMessage message) {
    final body = message.body;
    for (final pattern in _hardNonFinancialPatterns) {
      if (pattern.hasMatch(body)) return false;
    }
    if (_transactionVerbSignals.any((pattern) => pattern.hasMatch(body))) {
      return true;
    }
    for (final pattern in _softNonFinancialPatterns) {
      if (pattern.hasMatch(body)) return false;
    }
    return _financialSignals.any((pattern) => pattern.hasMatch(body));
  }
}
