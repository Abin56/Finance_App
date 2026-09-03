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
    r'\b(credited|received|deposited|added|refunded|reversed)\b',
    caseSensitive: false,
  );

  static final RegExp _debitPattern = RegExp(
    r'\b(debited|spent|paid|withdrawn|deducted|txn|transaction|sent|charged|transferred)\b',
    caseSensitive: false,
  );

  /// Status/completion wording with no explicit debit/credit keyword at all
  /// ("payment successful", "transaction failed", "payment is pending") —
  /// common in UPI-app-style confirmations and failure/reminder alerts that
  /// never use the bank-SMS-standard "debited"/"credited" phrasing. Checked
  /// only as [extractDirection]'s last resort, after the real credit/debit
  /// keywords above have both come up empty.
  static final RegExp _statusOnlyPattern = RegExp(
    r'\b(successful|successfully|completed|processed|failed|declined|unsuccessful|pending|processing)\b',
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

  static final RegExp _upiVpaPattern = RegExp(
    r'\b([\w.\-]{2,}@[a-zA-Z]{2,})\b',
  );

  /// `trf to NAME`, `to NAME on`, `at MERCHANT` — a best-effort merchant/
  /// counterparty name, trimmed to a sane display length.
  static final RegExp _merchantPattern = RegExp(
    "\\b(?:trf to|transfer to|to|at)\\s+([A-Za-z0-9&.\\-'\\s]{2,30}?)(?:\\s+on\\b|\\s+for\\b|\\.|,|\$)",
    caseSensitive: false,
  );

  /// `received from X`, `received payment from X`, `money received from X`,
  /// `transfer received from X`, or bare `from X` — a credit-side
  /// counterparty ("Rs.1000 received from Amazon") that [_merchantPattern]
  /// doesn't cover at all (it only recognizes "to"/"at" phrasing). The
  /// negative lookahead after "from" excludes a small set of generic
  /// pronoun-shaped openers ("your", "a", "an", "the") so a phrase like
  /// "payment received from your employer" is correctly left uncaptured
  /// rather than turning "your employer" into a fake merchant name — see
  /// [extractMerchant]'s doc comment for the same principle applied to
  /// support-email addresses.
  static final RegExp _merchantFromPattern = RegExp(
    "\\b(?:received\\s+(?:payment\\s+|money\\s+)?from|transfer\\s+received\\s+from|from)\\s+"
    "(?!your\\b|a\\b|an\\b|the\\b)"
    "([A-Za-z0-9&.\\-'\\s]{2,30}?)(?:\\s+on\\b|\\s+for\\b|\\s+using\\b|\\s+via\\b|\\s+through\\b|\\.|,|\$)",
    caseSensitive: false,
  );

  /// "Avl Bal", "Available Balance", "Bal" — text immediately before an
  /// amount match that marks it as an account-balance figure, not the
  /// amount actually transacted. Some messages state the balance *before*
  /// the transacted amount (e.g. "Avl Bal Rs.45,230.00. Rs.500.00 debited
  /// from a/c XX1234"), so [extractAmount] can't just take the first
  /// currency-shaped match in the body — it has to skip balance-adjacent
  /// ones first.
  static final RegExp _balanceContextPattern = RegExp(
    r'\b(avl\.?\s*bal|available\s*bal|bal(?:ance)?)\b',
    caseSensitive: false,
  );

  /// Picks the transacted amount out of a message that may state more than
  /// one currency figure (a balance, and the actual debit/credit amount).
  /// Prefers the first match that isn't immediately preceded by balance-
  /// context wording; falls back to the very first match if every candidate
  /// looks balance-adjacent (a balance-only figure is still better than no
  /// amount at all for a message that otherwise looks financial), which
  /// also keeps single-amount messages behaving exactly as before.
  static double? extractAmount(String body) {
    final primaryMatches = _amountPattern.allMatches(body).toList();
    final chosen =
        _preferNonBalanceMatch(body, primaryMatches) ??
        _amountByPattern.firstMatch(body);
    if (chosen == null) return null;
    final raw = chosen.group(1)?.replaceAll(',', '');
    return raw == null ? null : double.tryParse(raw);
  }

  static RegExpMatch? _preferNonBalanceMatch(
    String body,
    List<RegExpMatch> matches,
  ) {
    if (matches.isEmpty) return null;
    // The lookback window is clamped to start no earlier than the previous
    // match's own end — otherwise a 20-char window on a *later* amount can
    // bleed backward across a sentence boundary into an *earlier* amount's
    // own "Avl Bal" prefix and wrongly flag the later (real) amount as
    // balance-adjacent too (e.g. "Avl Bal Rs.45,230.00. Rs.500.00 debited"
    // — without this, the second match's window would still contain "Bal").
    var previousEnd = 0;
    for (final match in matches) {
      final rawWindowStart = match.start - 20;
      final windowStart =
          (rawWindowStart > previousEnd ? rawWindowStart : previousEnd).clamp(
            0,
            body.length,
          );
      final context = body.substring(windowStart, match.start);
      if (!_balanceContextPattern.hasMatch(context)) return match;
      previousEnd = match.end;
    }
    return matches.first;
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
      return creditIndex < debitIndex
          ? SmsTransactionDirection.credit
          : SmsTransactionDirection.debit;
    }
    // Last resort: no real debit/credit keyword at all, but the message
    // still reads as transaction-status wording ("payment successful",
    // "transaction failed", "payment is pending") — common in UPI-app-style
    // confirmations that skip the bank-SMS-standard "debited"/"credited"
    // phrasing entirely. Defaults to debit: the far more common case for a
    // personal-expense message, and — for the failed/pending subset
    // specifically — `TransactionStatusSignals`/`ReminderSignals` already
    // ensure `FinancialEvent.moneyMovement` ends up false regardless, so an
    // imperfect direction guess here has no practical consequence for those.
    // Never invents a direction when there is no transaction-shaped
    // language at all — a plain non-financial sentence still returns null.
    if (_statusOnlyPattern.hasMatch(body)) return SmsTransactionDirection.debit;
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
    final looksLikeUpi =
        body.toLowerCase().contains('upi') ||
        body.toLowerCase().contains('vpa');
    if (looksLikeUpi) {
      final vpaMatch = _upiVpaPattern.firstMatch(body);
      if (vpaMatch != null) return vpaMatch.group(1);
    }
    final merchantMatch = _merchantPattern.firstMatch(body);
    if (merchantMatch != null) return merchantMatch.group(1)?.trim();
    final fromMatch = _merchantFromPattern.firstMatch(body);
    return fromMatch?.group(1)?.trim();
  }

  static SmsTransactionCategory guessCategory(
    String body,
    SmsTransactionDirection? direction,
  ) {
    final lower = body.toLowerCase();
    // Specific-reason checks are all tried before the generic-rail checks
    // below (UPI/IMPS/NEFT/RTGS) — a salary/refund/bill credit often
    // *arrives via* UPI/NEFT/IMPS, and the more specific reason for the
    // money movement should win over the generic rail it travelled on.
    if (lower.contains('salary')) return SmsTransactionCategory.salaryCredit;
    if (lower.contains('cashback')) return SmsTransactionCategory.cashback;
    if (lower.contains('refund')) return SmsTransactionCategory.refund;
    if (RegExp(
          r'\binterest\b.{0,20}\bcredit',
          caseSensitive: false,
        ).hasMatch(body) ||
        RegExp(
          r'\bcredited\b.{0,20}\binterest\b',
          caseSensitive: false,
        ).hasMatch(body)) {
      return SmsTransactionCategory.interestCredit;
    }
    if (RegExp(
      r'\b(annual fee|late fee|late payment charge|finance charge|maintenance charge|penal charge|gst charged|charges levied|processing fee)\b',
      caseSensitive: false,
    ).hasMatch(body)) {
      return SmsTransactionCategory.bankFee;
    }
    if (lower.contains('cash deposit') || lower.contains('deposited cash'))
      return SmsTransactionCategory.cashDeposit;
    if (lower.contains('recharge')) return SmsTransactionCategory.recharge;
    if (lower.contains('bill payment') || lower.contains('bill paid'))
      return SmsTransactionCategory.billPayment;
    if (lower.contains('atm') && lower.contains('withdraw'))
      return SmsTransactionCategory.atmWithdrawal;
    if (lower.contains('emi')) return SmsTransactionCategory.loanEmiDebit;
    if (lower.contains('credit card') ||
        lower.contains('card ending') ||
        lower.contains('cc ')) {
      return SmsTransactionCategory.creditCardPurchase;
    }
    if (lower.contains('auto debit') ||
        lower.contains('autopay') ||
        lower.contains('standing instruction')) {
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
    if (lower.contains('purchase') ||
        lower.contains('spent') ||
        lower.contains('card')) {
      return SmsTransactionCategory.cardPurchase;
    }
    if (direction == SmsTransactionDirection.credit)
      return SmsTransactionCategory.bankCredit;
    if (direction == SmsTransactionDirection.debit)
      return SmsTransactionCategory.bankDebit;
    return SmsTransactionCategory.unknown;
  }
}
