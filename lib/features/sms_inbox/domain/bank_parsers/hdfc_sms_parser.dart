import '../bank_sender_matcher.dart';
import '../parsed_sms_transaction.dart';
import '../raw_sms_message.dart';
import '../sms_parser.dart';
import '../sms_regex_utils.dart';

/// HDFC Bank SMS (sender headers like `HDFCBK`/`HDFCBN`, e.g.
/// `VM-HDFCBK`, `AX-HDFCBN`). Confidence is high once the sender matches —
/// HDFC's phrasing ("debited from a/c", "credited to a/c") is captured well
/// by the shared regex set in `SmsRegexUtils`.
class HdfcSmsParser extends SmsParser {
  const HdfcSmsParser();

  @override
  bool canParse(RawSmsMessage message) => BankSenderMatcher.bankNameFor(message.address) == 'HDFC Bank';

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
      bankName: 'HDFC Bank',
      maskedAccountOrCard: SmsRegexUtils.extractMaskedAccount(body),
      referenceNumber: SmsRegexUtils.extractReferenceNumber(body),
    );
  }
}
