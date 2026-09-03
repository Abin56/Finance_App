/// Where a [MerchantIdentity] came from — every result exposes this, since
/// "how confident should I be" and "why was this suggested" both depend on
/// it. Distinct from [EvidenceSource] (`field_confidence.dart`), which
/// describes regex-vs-AI *agreement*; this describes which *tier* of the
/// resolution cascade actually produced the identity.
enum MerchantSource {
  /// This user has previously converted an SMS from this same normalized
  /// merchant key — the strongest signal, since it's evidence about this
  /// specific user, not a generalization. See `MerchantMemory`.
  userHistory,

  /// The SMS body itself named the merchant in a way a human would
  /// recognize (a real name, not a bare VPA/account-shaped token).
  explicitText,

  /// The UPI VPA's local part or handle matched a known merchant in
  /// [MerchantCatalog].
  vpaCatalog,

  /// Free text in the SMS matched a known merchant alias in
  /// [MerchantCatalog].
  merchantCatalog,

  /// A bank/UPI narration field (distinct from the general merchant-name
  /// regex) — reserved for a future, more structured narration parser;
  /// not populated by this phase's deterministic tiers.
  bankNarration,

  /// The AI inferred the identity — only ever trusted when backed by a
  /// quoted evidence substring, same "never invent" rule as everywhere else
  /// in this feature.
  aiInference,

  /// No tier could resolve an identity — [MerchantIdentity.isKnown] is
  /// always false when this is the source. A perfectly normal, honest
  /// outcome, never a fallback guess.
  unknown,
}

extension MerchantSourceX on MerchantSource {
  static MerchantSource fromName(String? name) {
    if (name == null) return MerchantSource.unknown;
    return MerchantSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => MerchantSource.unknown,
    );
  }
}
