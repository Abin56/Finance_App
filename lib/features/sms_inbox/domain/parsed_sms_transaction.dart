import 'sms_transaction_category.dart';
import 'sms_transaction_direction.dart';

/// The fields a `SmsParser` was able to extract from a financial SMS. Purely
/// a best-effort guess — every field here remains fully editable once the
/// user taps Convert, and nothing derived from this ever gets written to a
/// real FlowFi record without that explicit step.
class ParsedSmsTransaction {
  const ParsedSmsTransaction({
    required this.amount,
    required this.direction,
    required this.dateTime,
    required this.category,
    required this.confidence,
    required this.rawBody,
    this.merchantOrSender,
    this.bankName,
    this.maskedAccountOrCard,
    this.referenceNumber,
  });

  final double amount;
  final SmsTransactionDirection direction;
  final DateTime dateTime;
  final SmsTransactionCategory category;

  /// 0.0-1.0 — how confident the parser is in [amount]/[direction]. A
  /// bank-specific parser match is high confidence; the generic fallback
  /// parser is medium/low. Drives the card's confidence badge.
  final double confidence;
  final String rawBody;

  final String? merchantOrSender;
  final String? bankName;

  /// Last 4 digits of an account/card, when the SMS exposes them (e.g.
  /// `XX1234`, `xxxx1234`, `*1234`) — used to suggest which `Account`/
  /// `CreditCardProfile` this SMS belongs to.
  final String? maskedAccountOrCard;
  final String? referenceNumber;
}
