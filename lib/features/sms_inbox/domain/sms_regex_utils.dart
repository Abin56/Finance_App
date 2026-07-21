import 'sms_transaction_category.dart';
import 'sms_transaction_direction.dart';

/// Shared field-extraction regexes used by every `SmsParser`. Real-world
/// Indian bank/UPI SMS formats vary mostly in *phrasing*, not in how
/// amounts/references/masked accounts are written — centralizing extraction
/// here means every bank parser benefits from the same correctness fixes
/// instead of six near-duplicate regex sets drifting apart. Bank-specific
/// parsers still each own their own sender match + confidence + category
/// hinting, which is where per-bank behavior actually differs.
abstract class SmsRegexUtils {
  SmsRegexUtils._();

  static final RegExp _amountPattern = RegExp(
    r'(?:rs|inr|₹)\s?\.?\s?([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Some SBI UPI messages state the amount as `debited/credited by 20.00`
  /// with no currency marker at all (`rs`/`inr`/`₹`), so the primary
  /// [_amountPattern] never matches them. This is the fallback for exactly
  /// that phrasing.
  static final RegExp _amountByPattern = RegExp(
    r'\b(?:debited|credited)\s+by\s+([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final RegExp _creditPattern = RegExp(
    r'\b(credited|received|deposited|added)\b',
    caseSensitive: false,
  );

  static final RegExp _debitPattern = RegExp(
    r'\b(debited|spent|paid|withdrawn|deducted|txn|transaction)\b',
    caseSensitive: false,
  );

  static final RegExp _maskedAccountPattern = RegExp(
    r'\b(?:a/?c|acct|account|card)\b[^\d]{0,15}([xX*]{2,}|no\.?\s*)?(\d{4})\b',
    caseSensitive: false,
  );

  static final RegExp _referencePattern = RegExp(
    r'(?:ref(?:erence)?\.?\s*(?:no\.?|number)?|txn\s*id|UPI\s*Ref(?:\s*No)?)[:\s]*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );

  static final RegExp _upiVpaPattern = RegExp(r'\b([\w.\-]{2,}@[a-zA-Z]{2,})\b');

  /// `trf to NAME`, `to NAME on`, `at MERCHANT` — a best-effort merchant/
  /// counterparty name, trimmed to a sane display length.
  static final RegExp _merchantPattern = RegExp(
    "\\b(?:trf to|transfer to|to|at)\\s+([A-Za-z0-9&.\\-'\\s]{2,30}?)(?:\\s+on\\b|\\s+for\\b|\\.|,|\$)",
    caseSensitive: false,
  );

  static double? extractAmount(String body) {
    final match = _amountPattern.firstMatch(body) ?? _amountByPattern.firstMatch(body);
    if (match == null) return null;
    final raw = match.group(1)?.replaceAll(',', '');
    return raw == null ? null : double.tryParse(raw);
  }

  static SmsTransactionDirection? extractDirection(String body) {
    final creditMatch = _creditPattern.hasMatch(body);
    final debitMatch = _debitPattern.hasMatch(body);
    if (creditMatch && !debitMatch) return SmsTransactionDirection.credit;
    if (debitMatch && !creditMatch) return SmsTransactionDirection.debit;
    if (creditMatch && debitMatch) {
      // Both matched (rare) — trust whichever keyword appears first.
      final creditIndex = _creditPattern.firstMatch(body)!.start;
      final debitIndex = _debitPattern.firstMatch(body)!.start;
      return creditIndex < debitIndex ? SmsTransactionDirection.credit : SmsTransactionDirection.debit;
    }
    return null;
  }

  static String? extractMaskedAccount(String body) {
    final match = _maskedAccountPattern.firstMatch(body);
    return match?.group(2);
  }

  static String? extractReferenceNumber(String body) {
    return _referencePattern.firstMatch(body)?.group(1);
  }

  static String? extractMerchant(String body) {
    // The VPA pattern (`word@word`) matches any email-shaped substring, not
    // just a genuine UPI VPA — bank SMS routinely include a support email
    // ("mail us at customercare@hdfcbank.com") that would otherwise be
    // mistaken for the merchant. Only trust it when the message is actually
    // UPI-related; otherwise fall through to the merchant-name pattern.
    final looksLikeUpi = body.toLowerCase().contains('upi') || body.toLowerCase().contains('vpa');
    if (looksLikeUpi) {
      final vpaMatch = _upiVpaPattern.firstMatch(body);
      if (vpaMatch != null) return vpaMatch.group(1);
    }
    final merchantMatch = _merchantPattern.firstMatch(body);
    return merchantMatch?.group(1)?.trim();
  }

  static SmsTransactionCategory guessCategory(String body, SmsTransactionDirection? direction) {
    final lower = body.toLowerCase();
    // Specific-reason checks are all tried before the generic-rail checks
    // below (UPI/IMPS/NEFT/RTGS) — a salary/refund/bill credit often
    // *arrives via* UPI/NEFT/IMPS, and the more specific reason for the
    // money movement should win over the generic rail it travelled on.
    if (lower.contains('salary')) return SmsTransactionCategory.salaryCredit;
    if (lower.contains('refund')) return SmsTransactionCategory.refund;
    if (lower.contains('cash deposit') || lower.contains('deposited cash')) return SmsTransactionCategory.cashDeposit;
    if (lower.contains('bill payment') || lower.contains('bill paid')) return SmsTransactionCategory.billPayment;
    if (lower.contains('atm') && lower.contains('withdraw')) return SmsTransactionCategory.atmWithdrawal;
    if (lower.contains('emi')) return SmsTransactionCategory.loanEmiDebit;
    if (lower.contains('credit card') || lower.contains('card ending') || lower.contains('cc ')) {
      return SmsTransactionCategory.creditCardPurchase;
    }
    if (lower.contains('auto debit') || lower.contains('autopay') || lower.contains('standing instruction')) {
      return SmsTransactionCategory.autoDebit;
    }
    if (lower.contains('upi')) {
      return direction == SmsTransactionDirection.credit
          ? SmsTransactionCategory.upiReceive
          : SmsTransactionCategory.upiPayment;
    }
    if (RegExp(r'\b(imps|neft|rtgs)\b', caseSensitive: false).hasMatch(body)) {
      return SmsTransactionCategory.impsNeftRtgs;
    }
    if (lower.contains('wallet')) return SmsTransactionCategory.walletPayment;
    if (lower.contains('purchase') || lower.contains('spent') || lower.contains('card')) {
      return SmsTransactionCategory.cardPurchase;
    }
    if (direction == SmsTransactionDirection.credit) return SmsTransactionCategory.bankCredit;
    if (direction == SmsTransactionDirection.debit) return SmsTransactionCategory.bankDebit;
    return SmsTransactionCategory.unknown;
  }
}
