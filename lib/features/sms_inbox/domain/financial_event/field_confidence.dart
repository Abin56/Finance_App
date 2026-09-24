/// Where a [FieldConfidence]'s value came from — regex evidence, the AI's
/// opinion, or both. Never collapsed into a single number without keeping
/// this around: [EvidenceSource.bothDisagree] is the one case that must stay
/// visible to a reviewer rather than silently resolved, since picking a
/// winner and hiding the loser is exactly how a wrong amount slips through
/// unnoticed.
enum EvidenceSource { regexOnly, aiOnly, bothAgree, bothDisagree, none }

extension EvidenceSourceX on EvidenceSource {
  static EvidenceSource fromName(String? name) {
    if (name == null) return EvidenceSource.none;
    return EvidenceSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => EvidenceSource.none,
    );
  }
}

/// One field of a [FinancialEvent], plus how confident the reconciliation
/// was and what backed it. [value] is `null` whenever neither the regex
/// extractor nor the AI could determine it — this class exists precisely so
/// "unknown" is always representable and never silently guessed at (see the
/// SMS AI rebuild plan's "AI output must never invent data" principle).
class FieldConfidence<T> {
  const FieldConfidence({
    required this.value,
    required this.confidence,
    required this.source,
    this.aiEvidence,
    this.regexEvidence,
  });

  /// A field with no value from either signal — the honest "we don't know"
  /// state, never populated with a placeholder.
  const FieldConfidence.unknown()
    : value = null,
      confidence = 0.0,
      source = EvidenceSource.none,
      aiEvidence = null,
      regexEvidence = null;

  final T? value;

  /// 0.0-1.0.
  final double confidence;

  final EvidenceSource source;

  /// The AI's own quoted substring backing [value], when [source] is
  /// [EvidenceSource.aiOnly] or [EvidenceSource.bothAgree]/[EvidenceSource.bothDisagree]
  /// and the AI contributed a value — never shown as if it were the user's
  /// own text, only as an explanation of why this value was suggested.
  final String? aiEvidence;

  /// The regex match (or a description of it) backing [value], for the same
  /// explanatory purpose.
  final String? regexEvidence;
}
