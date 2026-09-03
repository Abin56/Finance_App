/// [CreditCardSemantics.detect]'s verdict on one message.
enum CreditCardSemanticVerdict {
  /// A charge made *to* the card (a purchase) — e.g. "credit card ending
  /// 1234 has been charged ₹5,000 at AMAZON."
  purchase,

  /// A payment made *toward* the card's balance, from a bank account —
  /// e.g. "₹5,000 payment received towards your credit card ending 1234."
  billPayment,

  /// The message mentions a credit card but the wording doesn't
  /// confidently resolve to either — worth an AI opinion (see
  /// `AiCallNecessity`).
  ambiguous,

  /// No credit-card wording at all — this detector has nothing to say.
  notApplicable,
}

/// Deterministic disambiguation between a credit-card **purchase** (money
/// charged to the card) and a credit-card **bill payment** (money paid
/// toward the card's balance) — the Phase 2 limitation this class exists to
/// close. A plain keyword match on "credit card" alone conflates the two
/// (both mention the phrase); this instead looks for the specific verb
/// shape each one uses in real bank SMS.
///
/// Deliberately narrow and conservative: `CreditCardSemanticVerdict.ambiguous`
/// is a completely valid, expected result for a genuinely unclear message —
/// `FinancialEventExtractor` treats that as a reason to consult the AI
/// (which reasons about the full sentence, not just these two patterns),
/// never as a reason to guess.
abstract class CreditCardSemantics {
  CreditCardSemantics._();

  static final RegExp _mentionsCreditCard = RegExp(
    r'\bcredit card\b',
    caseSensitive: false,
  );

  /// "credit card ... charged/spent", or "charged/spent ... credit card" —
  /// a charge *to* the card.
  static final RegExp _purchasePattern = RegExp(
    r'\bcredit card\b.{0,30}\b(charged|spent|purchase[d]?)\b|\b(charged|spent|purchase[d]?)\b.{0,30}\bcredit card\b',
    caseSensitive: false,
  );

  /// "payment ... received/credited ... towards ... credit card", or
  /// "credit card bill ... payment/paid" — money paid *toward* the card's
  /// balance.
  static final RegExp _billPaymentPattern = RegExp(
    r'\b(received|credited)\b.{0,30}\btowards\b.{0,20}\bcredit card\b'
    r'|\bpayment\b.{0,20}\btowards\b.{0,20}\bcredit card\b'
    r'|\bcredit card bill\b.{0,20}\b(payment|paid)\b'
    r'|\bcredit card\b.{0,20}\bpayment\b.{0,20}\b(received|successful|processed)\b',
    caseSensitive: false,
  );

  static CreditCardSemanticVerdict detect(String body) {
    if (!_mentionsCreditCard.hasMatch(body))
      return CreditCardSemanticVerdict.notApplicable;

    final isPurchase = _purchasePattern.hasMatch(body);
    final isBillPayment = _billPaymentPattern.hasMatch(body);

    if (isPurchase && !isBillPayment) return CreditCardSemanticVerdict.purchase;
    if (isBillPayment && !isPurchase)
      return CreditCardSemanticVerdict.billPayment;
    return CreditCardSemanticVerdict.ambiguous;
  }
}
