import '../parsed_sms_transaction.dart';
import '../raw_sms_message.dart';
import '../sms_parser.dart';
import '../sms_regex_utils.dart';
import '../sms_transaction_category.dart';

/// UPI apps (PhonePe/GPay/Paytm/BHIM/etc.) and unrecognized-bank UPI debit
/// alerts — matched by body content ("UPI") rather than sender id, since
/// these senders vary widely and aren't worth an exhaustive per-app list.
/// Tried after every bank-specific parser so a known bank's own UPI SMS
/// still gets that bank's (slightly higher) confidence.
class GenericUpiSmsParser extends SmsParser {
  const GenericUpiSmsParser();

  @override
  bool canParse(RawSmsMessage message) => RegExp(r'\bupi\b', caseSensitive: false).hasMatch(message.body);

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
      category: direction.name == 'credit' ? SmsTransactionCategory.upiReceive : SmsTransactionCategory.upiPayment,
      confidence: 0.7,
      rawBody: body,
      merchantOrSender: SmsRegexUtils.extractMerchant(body),
      maskedAccountOrCard: SmsRegexUtils.extractMaskedAccount(body),
      referenceNumber: SmsRegexUtils.extractReferenceNumber(body),
    );
  }
}
