import '../financial_event/financial_event.dart';
import '../obligation/financial_obligation.dart';
import '../obligation/obligation_link.dart';
import '../obligation/obligation_linker.dart';
import '../obligation/obligation_type.dart';
import 'event_relationship.dart';
import 'event_relationship_type.dart';
import 'match_confidence.dart';

/// Bridges a completed [FinancialEvent] to the Phase 4 obligation engine —
/// Parts 6, 11, 12, 13 of the task ("Integrate conceptually with the Phase
/// 4 Obligation Engine").
///
/// Deliberately a thin composition, not a modification: this class wraps
/// the existing, untouched `ObligationLinker`/`ObligationLookup` (Phase 4)
/// and only translates its verdict into an [EventRelationship] — refined
/// into [EventRelationshipType.installmentFor]/[subscriptionFor]/
/// [scheduledFor]/[paymentFor] using the matched obligation's own
/// `ObligationType`, which a bare `FinancialEvent` has no equivalent field
/// for. It never marks the obligation resolved itself (that stays the
/// caller's decision, matching `ObligationLinker`'s own "never
/// auto-execute" posture — see Safety rule 10).
class ObligationSettlementBridge {
  const ObligationSettlementBridge(
    this._linker, {
    this.getObligation,
  });

  final ObligationLinker _linker;

  /// Optional accessor for the full matched obligation, used only to
  /// refine [EventRelationshipType] by its `ObligationType`. When omitted,
  /// every match resolves to the generic [EventRelationshipType.paymentFor].
  final Future<FinancialObligation?> Function(String obligationId)? getObligation;

  /// Returns `null` when [candidate] does not represent confirmed money
  /// movement (only a completed payment can settle an obligation — Safety
  /// rule 1: a reminder must never itself be treated as settling anything)
  /// or when no outstanding obligation matched.
  Future<EventRelationship?> settle({
    required FinancialEvent candidate,
    required String id,
  }) async {
    if (candidate.moneyMovement.value != true) return null;

    final outcome = await _linker.link(
      amount: candidate.amount.value,
      merchantOrSender: candidate.merchant.value ?? candidate.normalizedSender,
      completedAt: candidate.eventDate,
      referenceNumber: candidate.referenceNumber,
    );

    if (outcome.result == ObligationLinkResult.noMatch) return null;

    if (outcome.result == ObligationLinkResult.possibleMatch) {
      return EventRelationship(
        id: id,
        sourceEventId: candidate.id,
        targetObligationId: outcome.matchedObligationId,
        relationshipType: EventRelationshipType.possibleMatch,
        confidence: MatchConfidence.medium,
        score: outcome.confidence * 100,
        matchedSignals: const [],
        evidence: [outcome.reason],
        reason: outcome.reason,
        needsReview: true,
        createdAt: candidate.eventDate,
      );
    }

    var type = EventRelationshipType.paymentFor;
    final obligationId = outcome.matchedObligationId;
    if (obligationId != null && getObligation != null) {
      final obligation = await getObligation!(obligationId);
      if (obligation != null) {
        type = _typeForObligation(obligation.obligationType);
      }
    }

    return EventRelationship(
      id: id,
      sourceEventId: candidate.id,
      targetObligationId: obligationId,
      relationshipType: type,
      confidence: MatchConfidence.high,
      score: outcome.confidence * 100,
      matchedSignals: const [],
      evidence: [outcome.reason],
      reason: outcome.reason,
      needsReview: false,
      createdAt: candidate.eventDate,
    );
  }

  EventRelationshipType _typeForObligation(ObligationType type) {
    switch (type) {
      case ObligationType.emiObligation:
      case ObligationType.loanObligation:
        return EventRelationshipType.installmentFor;
      case ObligationType.subscriptionRenewal:
        return EventRelationshipType.subscriptionFor;
      case ObligationType.upcomingDebit:
        return EventRelationshipType.scheduledFor;
      case ObligationType.duePayment:
      case ObligationType.creditCardDue:
      case ObligationType.billDue:
      case ObligationType.paymentReminder:
      case ObligationType.unknownObligation:
        return EventRelationshipType.paymentFor;
    }
  }
}
