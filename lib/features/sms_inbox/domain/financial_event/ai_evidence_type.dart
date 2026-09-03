/// What *kind* of text the AI is quoting as evidence for a claim — the
/// missing dimension pure substring grounding (`EvidenceGrounding`) cannot
/// see on its own. Grounding answers "did the AI actually quote real text
/// from the message?"; [AiEvidenceType] answers the next question this
/// phase exists to add: "does that *kind* of text actually support the
/// specific claim it's backing?"
///
/// The motivating case: "Rs.500 paid to xyz@upi" with the AI returning
/// `merchant: "Rahul"`, `evidence: "xyz@upi"`. The evidence is real — it
/// genuinely occurs in the message — so substring grounding alone accepts
/// it. But a VPA string is evidence of *the VPA*, never of a real-world
/// person's or business's identity; [AiClaimValidator] uses this type to
/// reject that claim even though it passed grounding.
enum AiEvidenceType {
  /// The evidence is (close to) the exact claimed value itself, quoted
  /// verbatim — e.g. merchant "Swiggy" backed by evidence "Swiggy". The
  /// strongest kind: the message says the thing directly.
  exactText,

  /// The evidence is a VPA string (`name@handle`). Real evidence that *a*
  /// VPA exists, never proof of who it belongs to — see this enum's class
  /// doc. Only strong enough to support a merchant claim when the VPA is
  /// also independently resolvable via the deterministic merchant catalog;
  /// [AiClaimValidator] never trusts a bare, uncatalogued VPA as identity
  /// evidence regardless of what name the AI attaches to it.
  vpa,

  /// The evidence names a business/merchant directly in prose (e.g. "at
  /// ABC Bakery", "to Swiggy") — strong support for a merchant claim.
  merchantName,

  /// The evidence names a payment app/rail (e.g. "using PhonePe") — strong
  /// support for a [PaymentProvider] claim, but never for a merchant claim
  /// (see [AiClaimValidator]'s "provider ≠ merchant" rule).
  providerName,

  /// The evidence is a transaction-status/type word ("debited", "declined",
  /// "reversed") — supports [FinancialEventType]/status-shaped claims, not
  /// identity or category claims.
  transactionKeyword,

  /// The evidence is an amount figure — never used to support a merchant
  /// or category claim (a number proves nothing about who was paid).
  amount,

  /// The evidence is an account/card reference — same rationale as
  /// [amount]: never sufficient to support merchant or category claims.
  account,

  /// The evidence is a free-text descriptive phrase not covered by the
  /// more specific types above (e.g. "for a restaurant order") — medium
  /// strength; enough to support a category claim, not enough on its own
  /// to support inventing a business name that isn't otherwise named.
  contextualPhrase,

  /// The AI didn't specify a type, or specified one this app doesn't
  /// recognize. Treated as the weakest tier — never enough to accept an
  /// identity claim on its own, matching this feature's "unknown is always
  /// preferable to hallucination" principle.
  unknown,
}

extension AiEvidenceTypeX on AiEvidenceType {
  /// The wire contract (`functions/src/types.ts`'s `AiEvidenceType`, and
  /// this app's own prompt/tool schema) uses snake_case strings
  /// (`"merchant_name"`, `"contextual_phrase"`, ...) rather than Dart's
  /// idiomatic camelCase enum member names — accepts both so a name coming
  /// straight off the wire and a name constructed in Dart (e.g. in tests)
  /// resolve the same way.
  static const Map<String, AiEvidenceType> _wireNames = {
    'exact_text': AiEvidenceType.exactText,
    'vpa': AiEvidenceType.vpa,
    'merchant_name': AiEvidenceType.merchantName,
    'provider_name': AiEvidenceType.providerName,
    'transaction_keyword': AiEvidenceType.transactionKeyword,
    'amount': AiEvidenceType.amount,
    'account': AiEvidenceType.account,
    'contextual_phrase': AiEvidenceType.contextualPhrase,
    'unknown': AiEvidenceType.unknown,
  };

  static AiEvidenceType fromName(String? name) {
    if (name == null) return AiEvidenceType.unknown;
    final byWireName = _wireNames[name];
    if (byWireName != null) return byWireName;
    return AiEvidenceType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AiEvidenceType.unknown,
    );
  }
}
