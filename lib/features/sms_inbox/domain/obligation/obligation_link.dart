/// What [ObligationLinker] decided about a newly-observed completed (or
/// resolving) [FinancialEvent] relative to outstanding
/// [FinancialObligation]s — mirrors `TransactionMatcher`'s
/// `FinancialEventMatchResult`/`TransactionMatchOutcome` pairing and its
/// transparency convention (always ship a human-readable [reason]).
enum ObligationLinkResult {
  /// A single outstanding obligation matched confidently enough to link and
  /// mark resolved.
  linkedResolved,

  /// More than one outstanding obligation could plausibly match — surfaced
  /// for manual confirmation, never auto-resolved (mirrors
  /// `FinancialEventMatchResult.possibleDuplicate`'s conservatism).
  possibleMatch,

  /// No outstanding obligation matched.
  noMatch,
}

class ObligationLinkOutcome {
  const ObligationLinkOutcome({
    required this.result,
    required this.reason,
    required this.confidence,
    this.matchedObligationId,
  });

  final ObligationLinkResult result;

  /// Set for [ObligationLinkResult.linkedResolved] and
  /// [ObligationLinkResult.possibleMatch] (the first/best candidate).
  final String? matchedObligationId;

  final String reason;

  /// 0.0-1.0.
  final double confidence;
}
