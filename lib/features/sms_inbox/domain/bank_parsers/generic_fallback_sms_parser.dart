import '../parsed_sms_transaction.dart';
import '../raw_sms_message.dart';
import '../sms_parser.dart';
import '../sms_regex_utils.dart';

/// Last-resort parser tried when no bank-specific or UPI parser matched.
/// Always "can parse" (it's the registry's fallback), but only actually
/// returns a result when an amount and direction were genuinely found —
/// otherwise the SMS still becomes an `SmsInboxItem` with `parsed == null`,
/// shown with every field blank/editable rather than dropped.
class GenericFallbackSmsParser extends SmsParser {
  const GenericFallbackSmsParser();

  @override
  bool canParse(RawSmsMessage message) => true;

  @override
  ParsedSmsTransaction? parse(RawSmsMessage message) {
    final body = message.body;
    final amount = SmsRegexUtils.extractAmount(body);
    final direction = SmsRegexUtils.extractDirection(body);
    if (amount == null || direction == null) return null;

    return ParsedSmsTransaction(
      amount: amount,
      direction: direction,
      dateTime: message.date,
      category: SmsRegexUtils.guessCategory(body, direction),
      confidence: 0.5,
      rawBody: body,
      merchantOrSender: SmsRegexUtils.extractMerchant(body),
      maskedAccountOrCard: SmsRegexUtils.extractMaskedAccount(body),
      referenceNumber: SmsRegexUtils.extractReferenceNumber(body),
    );
  }
}
