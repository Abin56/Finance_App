/// Where a merchant-identity or category signal came from, at a finer grain
/// than `EvidenceSource` (which only distinguishes regex vs AI on a single
/// field) — this layer resolves *two* things (identity, category) from
/// *several* possible signals at once, so each decision keeps its own
/// itemized trail rather than collapsing to one enum value.
enum MerchantEvidenceKind {
  /// The user has explicitly confirmed this exact merchant/category mapping
  /// before (via `MerchantMemory`) — the strongest evidence in the system.
  userConfirmed,

  /// A normalized VPA or merchant string exactly matched
  /// [MerchantIntelligenceCatalog].
  knownMerchantCatalog,

  /// A keyword in the SMS body/description matched a category-indicative
  /// term (e.g. "petrol", "bakery") — see `CategoryKeywordMatcher`.
  keywordMatch,

  /// The raw parser/regex layer supplied the value directly (e.g. the
  /// extracted merchant string itself, or a VPA).
  regex,

  /// An AI provider supplied the value, uncorroborated by any of the above.
  aiInference,

  /// No signal at all.
  none,
}

/// An itemized, human-readable trail for one merchant-intelligence decision —
/// deliberately verbose rather than a single confidence float, since the
/// whole point of this layer is that a reviewer (or a future debugging
/// session) can see *why* FlowFi concluded what it did, not just a number.
class MerchantEvidence {
  const MerchantEvidence({required this.kind, required this.details});

  const MerchantEvidence.none()
    : kind = MerchantEvidenceKind.none,
      details = const [];

  final MerchantEvidenceKind kind;

  /// Free-form notes, e.g. `['matched VPA swiggy@upi', 'catalog entry: Swiggy']`
  /// or `['keyword "petrol" found in body']`. Never includes anything not
  /// actually observed — no synthesized justifications.
  final List<String> details;

  MerchantEvidence withDetail(String detail) =>
      MerchantEvidence(kind: kind, details: [...details, detail]);

  @override
  String toString() =>
      details.isEmpty ? kind.name : '${kind.name}: ${details.join('; ')}';
}
