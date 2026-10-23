/// Extra gate for [SmsMessageSource.notification] messages only.
///
/// A notification from the messaging app can be a personal chat ("I paid
/// Rs 500 for lunch", "sent you Rs.1200 via UPI") that `SmsFinancialFilter`
/// alone accepts, since it only needs a transaction verb or a rupee amount.
/// Device-SMS rows keep the existing behaviour; for notification-sourced
/// rows this additionally requires evidence the text came from a bank/UPI
/// system: an account/card reference with digits, a VPA, a reference number,
/// or a balance line. Best-effort by design — a wallet alert with none of
/// these is skipped rather than risk ingesting private conversations.
///
/// Mirrored natively by `SmsFinancialPrefilter.hasBankEvidence` (Kotlin).
abstract class NotificationBankEvidence {
  NotificationBankEvidence._();

  static final List<RegExp> _signals = [
    RegExp(r'\b(a/c|acct|account|card)\b.{0,12}\d{3,4}', caseSensitive: false),
    RegExp(r'\bvpa\b', caseSensitive: false),
    RegExp(r'[a-z0-9._-]{2,}@[a-z]{2,}', caseSensitive: false),
    RegExp(r'\b(ref(erence)?|utr|rrn)\b.{0,12}\d{6,}', caseSensitive: false),
    RegExp(r'\b(avl|available)\.?\s*bal', caseSensitive: false),
    RegExp(r'\bbal(ance)?\s*[:.]?\s*(rs|inr|₹)', caseSensitive: false),
  ];

  static bool matches(String body) => _signals.any((s) => s.hasMatch(body));
}
