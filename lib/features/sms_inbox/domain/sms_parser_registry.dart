import 'bank_parsers/axis_sms_parser.dart';
import 'bank_parsers/generic_fallback_sms_parser.dart';
import 'bank_parsers/generic_upi_sms_parser.dart';
import 'bank_parsers/hdfc_sms_parser.dart';
import 'bank_parsers/icici_sms_parser.dart';
import 'bank_parsers/sbi_sms_parser.dart';
import 'parsed_sms_transaction.dart';
import 'raw_sms_message.dart';
import 'sms_parser.dart';

/// Tries each registered [SmsParser] in order and returns the first match's
/// result. Bank-specific parsers are listed before the UPI/generic
/// fallbacks so a recognized bank's SMS gets that bank's higher-confidence
/// extraction even when it also mentions UPI. Adding a new bank is a pure
/// addition here — insert it before [GenericUpiSmsParser], never touch the
/// others.
class SmsParserRegistry {
  const SmsParserRegistry();

  static const List<SmsParser> _parsers = [
    HdfcSmsParser(),
    IciciSmsParser(),
    SbiSmsParser(),
    AxisSmsParser(),
    GenericUpiSmsParser(),
    GenericFallbackSmsParser(),
  ];

  /// Runs the non-financial filter first, then the ordered parser chain.
  /// Returns null for anything that isn't a financial SMS at all (OTP,
  /// promo, spam, delivery, recharge reminders — these never become an
  /// `SmsInboxItem`). A financial-looking SMS whose fields couldn't be
  /// extracted still returns a non-null "recognized but unparsed" signal
  /// via [tryParse] returning null while [SmsFinancialFilter.isFinancial]
  /// is true — callers should check that separately (see
  /// `SmsInboxRepository.scanInbox`).
  ParsedSmsTransaction? tryParse(RawSmsMessage message) {
    for (final parser in _parsers) {
      if (parser.canParse(message)) {
        final result = parser.parse(message);
        if (result != null) return result;
      }
    }
    return null;
  }
}
