import '../bank_sender_matcher.dart';
import '../parsed_sms_transaction.dart';
import '../raw_sms_message.dart';
import '../sms_parser.dart';
import '../sms_regex_utils.dart';

/// State Bank of India SMS (sender headers like `SBIBNK`/`SBIINB`/`SBIPSG`/
/// `CBSSBI`).
class SbiSmsParser extends SmsParser {
  const SbiSmsParser();

  @override
  bool canParse(RawSmsMessage message) => BankSenderMatcher.bankNameFor(message.address) == 'State Bank of India';

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
      bankName: 'State Bank of India',
      maskedAccountOrCard: SmsRegexUtils.extractMaskedAccount(body),
      referenceNumber: SmsRegexUtils.extractReferenceNumber(body),
    );
  }
}
