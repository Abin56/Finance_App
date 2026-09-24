/// The inputs [AiCallNecessity.isNecessary] weighs — all cheap,
/// already-computed deterministic signals; this never triggers a second AI
/// call just to decide whether to make a first one.
class AiCallNecessityInput {
  const AiCallNecessityInput({
    required this.hasUnresolvedMerchantText,
    required this.hasUnresolvedCategory,
    required this.eventTypeIsAmbiguous,
  });

  /// True only when the SMS actually names a counterparty (a merchant/VPA
  /// string was extracted) **and** `MerchantIdentityResolver` could not
  /// resolve it. A message with no counterparty at all — a salary credit,
  /// an interest credit, a bank fee — is never penalized here just because
  /// there was nothing to look up; forcing an AI call on every salary SMS
  /// just because it has no "merchant" would contradict the whole point of
  /// this gate (see the SMS AI rebuild plan's "clear salary SMS → no AI
  /// required" example).
  final bool hasUnresolvedMerchantText;

  /// True only when category resolution didn't land on a real signal —
  /// the user's own history, the seed catalog, or a *specific* deterministic
  /// event type (salary, interest, a bank fee, cashback, an ATM withdrawal,
  /// a cash deposit). The generic upi/bank-debit/bank-credit/card-purchase
  /// fallback categories don't count as "resolved" here, since they carry
  /// no real category signal on their own.
  final bool hasUnresolvedCategory;

  /// True when a deterministic signal (credit-card purchase-vs-bill
  /// wording, a compound debit+reversal in one message) genuinely needs
  /// semantic judgment to resolve correctly — see `CreditCardSemantics` and
  /// the compound-reversal detection in `FinancialEventExtractor`.
  final bool eventTypeIsAmbiguous;
}

/// Decides whether an SMS is worth an AI call at all — see the SMS AI
/// rebuild plan's central cost/latency/privacy principle: "the objective is
/// NOT to make AI classify every SMS." A known-Swiggy-VPA payment or a
/// plain, unambiguous salary credit doesn't need a second opinion; a
/// message with an unresolved merchant, an unresolved category, or
/// genuinely ambiguous wording does.
///
/// Deliberately conservative in the direction of calling AI: any one
/// ambiguity signal is enough to say yes. The cost of an unnecessary AI
/// call is money and latency; the cost of *skipping* a call that would have
/// caught a real ambiguity is a wrong financial record — the asymmetry
/// means this errs toward calling, not toward skipping.
abstract class AiCallNecessity {
  AiCallNecessity._();

  static bool isNecessary(AiCallNecessityInput input) {
    if (input.eventTypeIsAmbiguous) return true;
    if (input.hasUnresolvedMerchantText) return true;
    if (input.hasUnresolvedCategory) return true;
    return false;
  }
}
