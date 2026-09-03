import 'match_confidence.dart';
import 'matching_signal.dart';
import 'event_relationship_type.dart';

/// One scored candidate target considered while resolving an
/// [EventRelationship] — surfaced in full when more than one candidate
/// ties for best (see [EventRelationship.alternativeCandidates] and Part
/// 15's ambiguity requirement: never arbitrarily choose one).
class EventRelationshipCandidate {
  const EventRelationshipCandidate({
    required this.score,
    required this.confidence,
    required this.matchedSignals,
    required this.reason,
    this.targetEventId,
    this.targetObligationId,
  });

  final String? targetEventId;
  final String? targetObligationId;
  final double score;
  final MatchConfidence confidence;
  final List<MatchedSignal> matchedSignals;
  final String reason;
}

/// The Part 2 relationship record: how one newly-processed
/// [FinancialEvent] (`sourceEventId`) relates to another already-known
/// `FinancialEvent` (`targetEventId`) or `FinancialObligation`
/// (`targetObligationId`) — never both, and possibly neither (a bare
/// [EventRelationshipType.newEvent] verdict has no target at all).
///
/// Deliberately not a boolean `isDuplicate` — every field here exists so a
/// reviewer (human or a future automation policy) can audit exactly why
/// this verdict was reached, matching the transparency convention every
/// other matcher in this feature already follows
/// (`TransactionMatchOutcome`, `ObligationLinkOutcome`).
class EventRelationship {
  const EventRelationship({
    required this.id,
    required this.sourceEventId,
    required this.relationshipType,
    required this.confidence,
    required this.score,
    required this.matchedSignals,
    required this.evidence,
    required this.reason,
    required this.needsReview,
    required this.createdAt,
    this.targetEventId,
    this.targetObligationId,
    this.alternativeCandidates = const [],
  });

  final String id;

  final String sourceEventId;

  /// Set when the target is another `FinancialEvent`. Mutually exclusive
  /// with [targetObligationId].
  final String? targetEventId;

  /// Set when the target is a Phase 4 `FinancialObligation`. Mutually
  /// exclusive with [targetEventId].
  final String? targetObligationId;

  final EventRelationshipType relationshipType;

  final MatchConfidence confidence;

  /// The raw weighted-signal score backing [confidence] — kept alongside
  /// the banded [confidence] level so a reviewer/future engine can see the
  /// underlying number, not just the bucket.
  final double score;

  final List<MatchedSignal> matchedSignals;

  /// Human-readable evidence lines, shown verbatim to a reviewer — never
  /// fabricated.
  final List<String> evidence;

  final String reason;

  /// True for every [EventRelationshipType] that is not
  /// [EventRelationshipTypeX.isDefinite] — i.e. [possibleMatch],
  /// [unknownRelationship], [relatedEvent] — and never auto-set to false
  /// just because [confidence] is [MatchConfidence.high]; see
  /// [EventRelationshipEngine] for the exact gate.
  final bool needsReview;

  final DateTime createdAt;

  /// Populated only for [EventRelationshipType.possibleMatch] — every
  /// candidate that tied for best, so a reviewer sees the full set rather
  /// than one arbitrarily chosen winner (Part 15).
  final List<EventRelationshipCandidate> alternativeCandidates;
}
