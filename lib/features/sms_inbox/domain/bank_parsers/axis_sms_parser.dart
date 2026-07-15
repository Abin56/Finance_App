import '../bank_sender_matcher.dart';
import '../parsed_sms_transaction.dart';
import '../raw_sms_message.dart';
import '../sms_parser.dart';
import '../sms_regex_utils.dart';

/// Axis Bank SMS (sender headers like `AXISBK`/`AXISBN`).
class AxisSmsParser extends SmsParser {
  const AxisSmsParser();

  @override
  bool canParse(RawSmsMessage message) => BankSenderMatcher.bankNameFor(message.address) == 'Axis Bank';

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
      confidence: 0.85,
      rawBody: body,
      merchantOrSender: SmsRegexUtils.extractMerchant(body),
      bankName: 'Axis Bank',
      maskedAccountOrCard: SmsRegexUtils.extractMaskedAccount(body),
      referenceNumber: SmsRegexUtils.extractReferenceNumber(body),
    );
  }
}
