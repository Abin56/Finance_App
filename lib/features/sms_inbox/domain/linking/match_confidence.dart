/// How strong the evidence is behind an [EventRelationship] verdict —
/// Part 14 of the task. Deliberately conservative: reaching [high] requires
/// either a unique identifier match or multiple independent corroborating
/// signals well above a minimum score, never a single signal no matter how
/// high its raw weight (see [EventRelationshipEngine]'s "hard signal count"
/// gate).
enum MatchConfidence {
  /// A unique identifier match (reference/UTR/transaction id), or multiple
  /// independent strong signals well above the minimum combined score.
  high,

  /// Multiple compatible signals, but no unique identifier and not enough
  /// combined weight for [high].
  medium,

  /// Exactly one signal category matched — by design, never enough to link
  /// (see Part 3: "amount alone / merchant alone / same sender alone —
  /// never sufficient").
  low,

  /// No qualifying signal at all.
  noMatch,
}

extension MatchConfidenceX on MatchConfidence {
  String get label {
    switch (this) {
      case MatchConfidence.high:
        return 'High';
      case MatchConfidence.medium:
        return 'Medium';
      case MatchConfidence.low:
        return 'Low';
      case MatchConfidence.noMatch:
        return 'No match';
    }
  }
}
