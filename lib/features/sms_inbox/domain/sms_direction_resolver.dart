import 'sms_transaction_direction.dart';

/// How a [DirectionVerdict] was reached.
enum DirectionEvidence {
  /// The message says WHOSE money moved: "debited from your a/c XX1234",
  /// "A/c XX1234 credited", "Rs.500 debited", "paid Rs.200 to NAME",
  /// "received from NAME", or a counterparty phrase that implies the user's
  /// side ("credited to NAME" → the user paid).
  contextual,

  /// Only bare verbs agreed ("spent", "credited") with no account/subject
  /// context. Usable, but not strong enough to skip a human look.
  keyword,
}

/// The result of [SmsDirectionResolver.resolve]. [direction] is `null` when
/// the message is unclear — conflicting evidence, or no debit/credit
/// evidence at all. A null direction is never defaulted to debit.
class DirectionVerdict {
  const DirectionVerdict._(this.direction, this.evidence, this.rule);

  const DirectionVerdict.unknown(String rule) : this._(null, null, rule);

  final SmsTransactionDirection? direction;
  final DirectionEvidence? evidence;

  /// Short machine-readable id of the rule that decided (evidence tracking).
  final String rule;

  bool get isKnown => direction != null;
  bool get isContextual => evidence == DirectionEvidence.contextual;
}

/// Decides debit vs credit from the WHOLE message, from the user's account
/// perspective — replacing the old "whichever keyword appears first wins"
/// tie-break and the "status-only wording defaults to debit" fallback.
///
/// 1. Contextual evidence is collected for both sides:
///    - own-account debit: "debited from your a/c", "A/c XX1234 debited",
///      "Rs.350 debited", "spent", "withdrawn", "paid/sent Rs.X to …";
///    - own-account credit: "credited to your a/c", "A/c XX1234 credited",
///      "Rs.500 credited/received/deposited", "received from …",
///      "credited back to your card";
///    - counterparty phrases flip sides: "credited to ABIN JOHN" (someone
///      else's account was credited → the user's was debited), "debited
///      from VPA x@y" (someone else was debited → the user was credited).
///    Exactly one side → that side, [DirectionEvidence.contextual].
///    Both sides → unknown (e.g. a self-transfer naming two accounts).
/// 2. No context at all → bare verbs. Exactly one side → that side,
///    [DirectionEvidence.keyword]. Both or neither → unknown.
///
/// "successful", "completed", "processed", "failed", "pending" are never
/// direction evidence on their own.
abstract class SmsDirectionResolver {
  SmsDirectionResolver._();

  // An account/card mention. `a/c` has no trailing boundary so a glued mask
  // (`A/cXX9585`) still counts; bare `ac` needs one ("across" must not).
  // An account mention that is NOT "a/c XX1234 of RAMESH" (someone else's).
  static const String _acc =
      r"(?:a/c|\bac\b|\bacct\b|\baccount\b|\bcard\b)(?!\s*(?:no\.?\s*)?[x*]*\d{0,6}\s+of\s+(?!your\b|you\b)[a-z])";
  static const String _amt = r'(?:rs\.?|inr|₹)\s?\.?\s?[\d,]+(?:\.\d{1,2})?';
  // Up to three words between a verb and the account ("from HDFC Bank a/c").
  static const String _gap = r'(?:[\w&.\-]+\s+){0,3}?';
  // Text between an account mention and its verb, never crossing a sentence
  // break, another debit/credit verb or an "and" (so "a/c XX1 debited …; ABC
  // credited" and "debited A/cXX9585 and credited to NAME" can't read as
  // "a/c … credited").
  static const String _tempered =
      r'(?:(?!\b(?:debited|credited|deducted|and)\b)[^.;\n]){0,30}?';
  static const String _be = r'(?:is\s+|has\s+been\s+|was\s+|got\s+)?';

  static RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

  static final List<(String, RegExp)> _ownDebit = [
    // "debited from your a/c", "debited A/cXX9585", "withdrawn from HDFC a/c"
    (
      'debited-from-account',
      _re(
        '\\b(?:debited|deducted|withdrawn)\\s+(?:from\\s+)?(?:your\\s+|ur\\s+)?$_gap$_acc',
      ),
    ),
    // "A/c XX1234 debited", "your account is debited"
    ('account-debited', _re('$_acc$_tempered\\b$_be(?:debited|deducted)\\b')),
    // "Rs.350.00 debited" — the alert's own account, by Indian bank convention
    ('amount-debited', _re('$_amt\\s+$_be(?:debited|deducted|withdrawn)\\b')),
    // "spent" is only ever the user's own spend
    ('spent', _re(r'\bspent\b')),
    // "You paid Rs.200 to X", "Sent Rs.500.00 From HDFC Bank A/C x1234 To X"
    (
      'paid-amount-to',
      _re('\\b(?:paid|sent|transferred)\\s+$_amt\\s+(?:to|from)\\b'),
    ),
    ('amount-paid-to', _re('$_amt\\s+$_be(?:paid|sent|transferred)\\s+to\\b')),
    // "ATM withdrawal of Rs.2000", "Rs 2000 withdrawn at ATM"
    ('atm-withdrawal', _re(r'\batm\b.{0,30}\bwithdraw')),
    // "UPI payment of ₹500 to ABC completed"
    ('payment-of-amount-to', _re('\\bpayment\\s+of\\s+$_amt\\s+to\\b')),
    // "Transaction successful for INR 500 at a merchant"
    ('amount-at-merchant', _re('\\b(?:for|of)\\s+$_amt\\s+at\\b')),
  ];

  static final List<(String, RegExp)> _ownCredit = [
    // "credited to your a/c", "credited back to your Debit Card XX1234",
    // "credited in HDFC Bank A/c XX12", "deposited into a/c"
    (
      'credited-to-account',
      _re(
        '\\b(?:credited|deposited|refunded|reversed)\\s+(?:back\\s+)?(?:to|in|into)\\s+(?:your\\s+|ur\\s+)?$_gap$_acc',
      ),
    ),
    // "A/c XX1234 credited", "your account has been credited"
    // ("… credited to NAME" is the counterparty, handled below)
    (
      'account-credited',
      _re('$_acc$_tempered\\b$_be(?:credited)\\b(?!\\s+to\\b)'),
    ),
    // "Rs.500 credited", "Rs 500 received", "Rs 500 deposited" — but NOT
    // "Rs 500 credited to ABIN JOHN" (that is a counterparty phrase, below)
    (
      'amount-credited',
      _re('$_amt\\s+$_be(?:credited|deposited|received)\\b(?!\\s+to\\b)'),
    ),
    // "received Rs.500", "You have received a payment", "received from X"
    (
      'received-amount',
      _re('\\breceived\\s+(?:$_amt|(?:a\\s+)?payment|money)'),
    ),
    ('received-from', _re(r'\breceived\s+(?:\w+\s+){0,2}?from\b')),
    ('credited-back', _re(r'\bcredited\s+back\b')),
    // "Money Received - INR 500.00 in your HDFC Bank A/c xx1234"
    (
      'amount-into-account',
      _re(
        '$_amt\\s+(?:has\\s+been\\s+)?(?:credited\\s+)?(?:in|into)\\s+(?:your\\s+|ur\\s+)?$_gap$_acc',
      ),
    ),
    ('money-received', _re(r'\bmoney\s+received\b')),
  ];

  // Someone else's account was credited → the user paid.
  static final RegExp _counterpartyCredited = _re(
    '\\bcredited\\s+to\\s+(?:vpa\\s+|beneficiary\\s+|payee\\s+)?'
    '(?!(?:your|ur|the\\s+account|a/c|ac\\b|acct\\b|account\\b|card\\b))'
    "[A-Za-z0-9][\\w.\\-@' ]{1,40}",
  );

  // Someone else was debited → the user received. Never fires when an
  // account mention follows closely ("debited from HDFC Bank a/c").
  static final RegExp _counterpartyDebited = _re(
    '\\bdebited\\s+from\\s+(?!(?:your|ur)\\b)'
    '(?![^.;\\n]{0,30}?$_acc)'
    '(?:vpa\\s+)?[A-Za-z0-9]',
  );

  static final RegExp _weakDebit = _re(
    r'\b(debited|deducted|spent|paid|withdrawn|sent|charged|transferred|purchased?)\b',
  );
  static final RegExp _weakCredit = _re(
    r'\b(credited|received|deposited|refunded|reversed)\b',
  );

  static DirectionVerdict resolve(String body) {
    final debitRules = [
      for (final (id, re) in _ownDebit)
        if (re.hasMatch(body)) id,
      if (_counterpartyCredited.hasMatch(body)) 'counterparty-credited',
    ];
    final creditRules = [
      for (final (id, re) in _ownCredit)
        if (re.hasMatch(body)) id,
      if (_counterpartyDebited.hasMatch(body)) 'counterparty-debited',
    ];

    if (debitRules.isNotEmpty && creditRules.isEmpty) {
      return DirectionVerdict._(
        SmsTransactionDirection.debit,
        DirectionEvidence.contextual,
        debitRules.first,
      );
    }
    if (creditRules.isNotEmpty && debitRules.isEmpty) {
      return DirectionVerdict._(
        SmsTransactionDirection.credit,
        DirectionEvidence.contextual,
        creditRules.first,
      );
    }
    if (debitRules.isNotEmpty && creditRules.isNotEmpty) {
      return const DirectionVerdict.unknown('conflicting-context');
    }

    final weakDebit = _weakDebit.hasMatch(body);
    final weakCredit = _weakCredit.hasMatch(body);
    if (weakDebit && !weakCredit) {
      return const DirectionVerdict._(
        SmsTransactionDirection.debit,
        DirectionEvidence.keyword,
        'keyword-debit',
      );
    }
    if (weakCredit && !weakDebit) {
      return const DirectionVerdict._(
        SmsTransactionDirection.credit,
        DirectionEvidence.keyword,
        'keyword-credit',
      );
    }
    return DirectionVerdict.unknown(
      weakDebit ? 'conflicting-keywords' : 'no-direction-evidence',
    );
  }
}
