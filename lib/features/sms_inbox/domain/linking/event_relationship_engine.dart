import '../financial_event/financial_event.dart';
import '../financial_event/financial_event_type.dart';
import '../financial_event/transaction_status.dart';
import '../merchant/merchant_key.dart';
import 'event_relationship.dart';
import 'event_relationship_lookup.dart';
import 'event_relationship_type.dart';
import 'match_confidence.dart';
import 'matching_signal.dart';
import 'reference_normalizer.dart';

/// Deterministic, weighted multi-signal matching between one newly-processed
/// `FinancialEvent` (the "candidate") and the pool of already-known events —
/// Part 3 of the task. Deliberately layered *alongside*, not on top of or
/// instead of, the existing `TransactionMatcher` (which stays untouched and
/// keeps driving today's production auto-linking in
/// `sms_inbox_providers.dart`) — this engine is the richer Phase 5
/// replacement/extension that a future integration can swap in, exposed
/// through the same "read candidates, return a verdict, never write
/// anything" posture `TransactionMatcher` and `ObligationLinker` both use.
///
/// # The gating rule (Part 3's "never sufficient alone")
///
/// Every matched signal is grouped into "hard" (identity-bearing:
/// reference, amount, merchant, account/card) or "soft" (corroborating
/// only: temporal proximity, sender, payment provider/method, direction,
/// event type). [MatchConfidence.high]/[MatchConfidence.medium] both
/// require **at least two matched hard-signal categories** (or a single
/// exact reference match, which the task calls "extremely strong" on its
/// own) — a single hard signal, no matter how many soft signals reinforce
/// it, is hard-capped at [MatchConfidence.low] and never becomes a link.
/// Soft signals alone (e.g. only the same SMS sender) never even reach
/// [MatchConfidence.low] — they resolve to [MatchConfidence.noMatch].
class EventRelationshipEngine {
  const EventRelationshipEngine(this._lookup);

  final EventRelationshipLookup _lookup;

  static const _referenceWeight = 60.0;
  static const _amountWeight = 12.0;
  static const _merchantWeight = 12.0;
  static const _accountWeight = 10.0;
  static const _cardWeight = 8.0;
  static const _providerWeight = 5.0;
  static const _paymentMethodWeight = 3.0;
  static const _directionWeight = 3.0;
  static const _senderWeight = 3.0;
  static const _eventTypeWeight = 4.0;
  static const _closeTemporalWeight = 10.0;
  static const _midTemporalWeight = 6.0;
  static const _farTemporalWeight = 2.0;

  /// The signal categories that count toward the "at least two" gate —
  /// everything else only adds to the raw score, never to this count.
  static const _hardSignals = {
    MatchingSignal.referenceId,
    MatchingSignal.amount,
    MatchingSignal.merchant,
    MatchingSignal.accountOrCard,
    MatchingSignal.creditCardIdentifier,
  };

  static const _highScoreThreshold = 35.0;
  static const _mediumScoreThreshold = 18.0;

  static const _defaultWindow = Duration(days: 60);

  /// Candidates within this score of the best score are treated as tied —
  /// see Part 15: never arbitrarily pick one of several comparable
  /// candidates.
  static const _tieEpsilon = 3.0;

  Future<EventRelationship> evaluate({
    required FinancialEvent candidate,
    required String id,
    Duration window = _defaultWindow,
  }) async {
    final pool = <String, FinancialEvent>{};

    if (candidate.referenceNumber != null) {
      for (final e in await _lookup.findByReferenceNumber(
        candidate.referenceNumber!,
      )) {
        pool[e.id] = e;
      }
    }
    for (final e in await _lookup.findBySenderAmountWindow(
      normalizedSender: candidate.normalizedSender,
      amount: candidate.amount.value,
      start: candidate.eventDate.subtract(window),
      end: candidate.eventDate.add(window),
    )) {
      pool[e.id] = e;
    }
    for (final e in await _lookup.findByMerchantWindow(
      merchant: candidate.merchant.value,
      start: candidate.eventDate.subtract(window),
      end: candidate.eventDate.add(window),
    )) {
      pool[e.id] = e;
    }
    for (final e in await _lookup.findByAmountWindow(
      amount: candidate.amount.value,
      start: candidate.eventDate.subtract(window),
      end: candidate.eventDate.add(window),
    )) {
      pool[e.id] = e;
    }
    pool.remove(candidate.id);

    if (pool.isEmpty) {
      return _newEvent(candidate: candidate, id: id);
    }

    final scored = pool.values
        .map((target) => _score(candidate, target))
        .where((c) => c.confidence != MatchConfidence.noMatch)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) {
      return _newEvent(candidate: candidate, id: id);
    }

    final best = scored.first;
    final tied = scored
        .where((c) => (best.score - c.score).abs() <= _tieEpsilon)
        .toList();

    if (tied.length > 1) {
      return EventRelationship(
        id: id,
        sourceEventId: candidate.id,
        relationshipType: EventRelationshipType.possibleMatch,
        confidence: MatchConfidence.medium,
        score: best.score,
        matchedSignals: best.matchedSignals,
        evidence: tied.map((c) => c.reason).toList(),
        reason:
            '${tied.length} candidate events matched with comparable confidence — surfaced for manual review rather than auto-linked.',
        needsReview: true,
        createdAt: candidate.eventDate,
        alternativeCandidates: tied,
      );
    }

    switch (best.confidence) {
      // A refund/reversal/transfer verdict is decided from the candidate's
      // OWN already-resolved fields, never from how strong the match score
      // against a particular target happens to be — so it must not wait
      // for HIGH (or even MEDIUM) confidence to be recognized (Part 9: a
      // refund/reversal must never be misread as an ordinary
      // duplicate/unrelated event merely because the corroborating signal
      // count was thin — a partial refund, for instance, often shares only
      // its merchant with the original charge, a single hard signal). The
      // specific target is still uncertain below HIGH, so this always
      // stays `needsReview: true` at LOW/MEDIUM.
      case MatchConfidence.low:
      case MatchConfidence.medium:
        final target = pool[best.targetEventId]!;
        final semanticType = _semanticTypeFromCandidate(candidate, target);
        if (semanticType != null) {
          return EventRelationship(
            id: id,
            sourceEventId: candidate.id,
            targetEventId: target.id,
            relationshipType: semanticType,
            confidence: best.confidence,
            score: best.score,
            matchedSignals: best.matchedSignals,
            evidence: [best.reason],
            reason: _reasonFor(semanticType, best),
            needsReview: true,
            createdAt: candidate.eventDate,
            alternativeCandidates: [best],
          );
        }
        if (best.confidence == MatchConfidence.low) {
          return _newEvent(candidate: candidate, id: id);
        }
        return EventRelationship(
          id: id,
          sourceEventId: candidate.id,
          targetEventId: best.targetEventId,
          relationshipType: EventRelationshipType.possibleMatch,
          confidence: best.confidence,
          score: best.score,
          matchedSignals: best.matchedSignals,
          evidence: [best.reason],
          reason: best.reason,
          needsReview: true,
          createdAt: candidate.eventDate,
          alternativeCandidates: [best],
        );

      case MatchConfidence.high:
        final target = pool[best.targetEventId]!;

        // Same reference number but a conflicting amount — the strongest
        // identity signal disagreeing with a hard fact is exactly the case
        // that must stay flagged for review, never silently merged (mirrors
        // `TransactionMatcher._matchByReference`'s existing precedent: same
        // reference + different amount -> possibleDuplicate, not a blind
        // merge). Refunds/reversals are exempt — a partial refund
        // legitimately has a smaller amount than the original charge.
        final refMatch = best.matchedSignals.any(
          (s) => s.signal == MatchingSignal.referenceId,
        );
        final amountsConflict =
            candidate.amount.value != null &&
            target.amount.value != null &&
            (candidate.amount.value! - target.amount.value!).abs() >= 0.01;
        final candidateIsSettlement =
            candidate.eventType == FinancialEventType.refund ||
            candidate.eventType == FinancialEventType.reversal ||
            candidate.transactionStatus.value == TransactionStatus.refunded ||
            candidate.transactionStatus.value == TransactionStatus.reversed;
        if (refMatch && amountsConflict && !candidateIsSettlement) {
          return EventRelationship(
            id: id,
            sourceEventId: candidate.id,
            targetEventId: target.id,
            relationshipType: EventRelationshipType.possibleMatch,
            confidence: MatchConfidence.medium,
            score: best.score,
            matchedSignals: best.matchedSignals,
            evidence: [
              'Same reference number as event ${target.id}, but the amount differs — please confirm.',
            ],
            reason:
                'Same reference number as an existing event, but a different amount — surfaced for manual review rather than merged.',
            needsReview: true,
            createdAt: candidate.eventDate,
            alternativeCandidates: [best],
          );
        }

        final type = _resolveType(candidate, target);
        return EventRelationship(
          id: id,
          sourceEventId: candidate.id,
          targetEventId: target.id,
          relationshipType: type,
          confidence: best.confidence,
          score: best.score,
          matchedSignals: best.matchedSignals,
          evidence: [best.reason],
          reason: _reasonFor(type, best),
          needsReview: !type.isDefinite,
          createdAt: candidate.eventDate,
        );

      case MatchConfidence.noMatch:
        return _newEvent(candidate: candidate, id: id);
    }
  }

  EventRelationshipCandidate _score(FinancialEvent candidate, FinancialEvent target) {
    final signals = <MatchedSignal>[];
    var score = 0.0;

    final refMatch = ReferenceNormalizer.matches(
      candidate.referenceNumber,
      target.referenceNumber,
    );
    if (refMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.referenceId,
          weight: _referenceWeight,
          description: 'Same reference/UTR/transaction number.',
        ),
      );
      score += _referenceWeight;
    }

    final amountMatch =
        candidate.amount.value != null &&
        target.amount.value != null &&
        (candidate.amount.value! - target.amount.value!).abs() < 0.01;
    if (amountMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.amount,
          weight: _amountWeight,
          description: 'Same amount.',
        ),
      );
      score += _amountWeight;
    }

    final merchantMatch = _merchantsMatch(
      candidate.merchant.value,
      target.merchant.value,
    );
    if (merchantMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.merchant,
          weight: _merchantWeight,
          description: 'Same merchant.',
        ),
      );
      score += _merchantWeight;
    }

    final accountMatch =
        candidate.accountMatch.value != null &&
        candidate.accountMatch.value == target.accountMatch.value;
    if (accountMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.accountOrCard,
          weight: _accountWeight,
          description: 'Same account.',
        ),
      );
      score += _accountWeight;
    }

    final cardMatch =
        candidate.matchedCardId != null &&
        candidate.matchedCardId == target.matchedCardId;
    if (cardMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.creditCardIdentifier,
          weight: _cardWeight,
          description: 'Same credit card.',
        ),
      );
      score += _cardWeight;
    }

    final providerMatch =
        candidate.paymentProvider.value != null &&
        candidate.paymentProvider.value == target.paymentProvider.value;
    if (providerMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.paymentProvider,
          weight: _providerWeight,
          description: 'Same payment provider/app.',
        ),
      );
      score += _providerWeight;
    }

    final methodMatch =
        candidate.paymentMethod.value != null &&
        candidate.paymentMethod.value == target.paymentMethod.value;
    if (methodMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.paymentMethod,
          weight: _paymentMethodWeight,
          description: 'Same payment method.',
        ),
      );
      score += _paymentMethodWeight;
    }

    if (candidate.direction == target.direction) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.direction,
          weight: _directionWeight,
          description: 'Same direction (debit/credit).',
        ),
      );
      score += _directionWeight;
    }

    final senderMatch =
        candidate.normalizedSender != null &&
        candidate.normalizedSender == target.normalizedSender;
    if (senderMatch) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.smsSender,
          weight: _senderWeight,
          description: 'Same SMS sender.',
        ),
      );
      score += _senderWeight;
    }

    if (candidate.eventType == target.eventType) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.eventType,
          weight: _eventTypeWeight,
          description: 'Same event type.',
        ),
      );
      score += _eventTypeWeight;
    }

    final gap = candidate.eventDate.difference(target.eventDate).abs();
    if (gap <= const Duration(hours: 1)) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.temporalProximity,
          weight: _closeTemporalWeight,
          description: 'Within 1 hour of each other.',
        ),
      );
      score += _closeTemporalWeight;
    } else if (gap <= const Duration(hours: 24)) {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.temporalProximity,
          weight: _midTemporalWeight,
          description: 'Within 24 hours of each other.',
        ),
      );
      score += _midTemporalWeight;
    } else {
      signals.add(
        const MatchedSignal(
          signal: MatchingSignal.temporalProximity,
          weight: _farTemporalWeight,
          description: 'Within the lookback window.',
        ),
      );
      score += _farTemporalWeight;
    }

    final hardCount = signals
        .map((s) => s.signal)
        .toSet()
        .where(_hardSignals.contains)
        .length;

    MatchConfidence confidence;
    if (refMatch) {
      confidence = MatchConfidence.high;
    } else if (hardCount == 0) {
      confidence = MatchConfidence.noMatch;
    } else if (hardCount == 1) {
      confidence = MatchConfidence.low;
    } else if (score >= _highScoreThreshold) {
      confidence = MatchConfidence.high;
    } else if (score >= _mediumScoreThreshold) {
      confidence = MatchConfidence.medium;
    } else {
      confidence = MatchConfidence.low;
    }

    return EventRelationshipCandidate(
      targetEventId: target.id,
      score: score,
      confidence: confidence,
      matchedSignals: signals,
      reason: _describeCandidate(target, signals, confidence, refMatch),
    );
  }

  bool _merchantsMatch(String? a, String? b) {
    final na = MerchantKey.normalize(a);
    final nb = MerchantKey.normalize(b);
    return na != null && nb != null && na == nb;
  }

  String _describeCandidate(
    FinancialEvent target,
    List<MatchedSignal> signals,
    MatchConfidence confidence,
    bool refMatch,
  ) {
    if (refMatch) {
      return 'Event ${target.id}: exact reference/UTR match (${confidence.label} confidence).';
    }
    final names = signals.map((s) => s.signal.name).join(', ');
    return 'Event ${target.id}: matched on [$names] (${confidence.label} confidence, score ${signals.fold<double>(0, (a, s) => a + s.weight).toStringAsFixed(1)}).';
  }

  /// Resolves the specific relationship type once a single [target] has
  /// been confidently matched — Parts 5, 6/7, 8, 9, 10.
  ///
  /// Order matters: refund/reversal is decided first purely from
  /// [candidate]'s own resolved fields (never inferred from similarity to
  /// [target]), so a refund is never mistaken for a duplicate just because
  /// its amount/merchant/timing happen to match the original charge — see
  /// Safety rule "refund/reversal must never become a duplicate."
  /// Refund/reversal/transfer-pair verdicts, decided purely from
  /// [candidate]'s own already-resolved fields (never from how well it
  /// happens to score against [target]) — see Part 9's precedence
  /// requirement. Returns `null` when none apply, so callers at any
  /// confidence tier can check this first without committing to a type.
  EventRelationshipType? _semanticTypeFromCandidate(
    FinancialEvent candidate,
    FinancialEvent target,
  ) {
    final candidateIsRefund =
        candidate.eventType == FinancialEventType.refund ||
        candidate.transactionStatus.value == TransactionStatus.refunded;
    if (candidateIsRefund) return EventRelationshipType.refundOf;

    final candidateIsReversal =
        candidate.eventType == FinancialEventType.reversal ||
        candidate.transactionStatus.value == TransactionStatus.reversed;
    if (candidateIsReversal) return EventRelationshipType.reversalOf;

    if (candidate.isOwnAccountTransfer &&
        target.isOwnAccountTransfer &&
        candidate.direction != target.direction) {
      return EventRelationshipType.transferPair;
    }

    return null;
  }

  EventRelationshipType _resolveType(FinancialEvent candidate, FinancialEvent target) {
    final semanticType = _semanticTypeFromCandidate(candidate, target);
    if (semanticType != null) return semanticType;

    // Both amounts are known and they conflict — one real transaction
    // cannot have two different amounts, so this pair can never be the
    // SAME transaction (duplicate/update/reminderFor), no matter how well
    // everything else scored. (Refunds are already handled above, since a
    // partial refund legitimately has a smaller amount.)
    final amountsKnownAndConflict =
        candidate.amount.value != null &&
        target.amount.value != null &&
        (candidate.amount.value! - target.amount.value!).abs() >= 0.01;
    if (amountsKnownAndConflict) {
      return EventRelationshipType.relatedEvent;
    }

    // A debit and a credit are never the same underlying transaction
    // reported twice/updated — opposite [direction] rules out
    // duplicate/update/reminderFor, the same way a conflicting amount does
    // above. (Refunds/reversals/transfers are already handled above and
    // are exempt — they are EXPECTED to carry the opposite direction from
    // the charge they resolve.)
    if (candidate.direction != target.direction) {
      return EventRelationshipType.relatedEvent;
    }

    final candidateMoved = candidate.moneyMovement.value == true;
    final targetMoved = target.moneyMovement.value == true;
    final candidateStatus = candidate.transactionStatus.value;
    final targetStatus = target.transactionStatus.value;

    // A status transition on the SAME underlying transaction attempt
    // (target already had a resolved pending/failed/etc. status) takes
    // priority over [reminderFor] below — [reminderFor] is reserved for a
    // target that was never itself a transaction attempt at all (a
    // reminder/scheduled notice, which never gets a resolved
    // transactionStatus). Checking status-transition first is what keeps
    // Part 8's pending -> successful/failed/reversed lifecycle intact
    // rather than being pre-empted by the broader moved/not-moved check.
    if (candidateStatus != null &&
        targetStatus != null &&
        candidateStatus != targetStatus) {
      switch (candidateStatus) {
        case TransactionStatus.pending:
          return EventRelationshipType.pendingUpdate;
        case TransactionStatus.failed:
          return EventRelationshipType.failedUpdate;
        case TransactionStatus.reversed:
          return EventRelationshipType.reversalOf;
        case TransactionStatus.refunded:
          return EventRelationshipType.refundOf;
        case TransactionStatus.success:
          return EventRelationshipType.update;
        case TransactionStatus.unknown:
          break;
      }
    }

    if (candidateMoved && !targetMoved && targetStatus == null) {
      return EventRelationshipType.reminderFor;
    }

    // Weak-fallback duplicate path: below HIGH-confidence-with-reference,
    // amount+merchant+timing alone is never sufficient to call two events
    // the same transaction reported twice — a new purchase must not be
    // classified as a duplicate of an earlier refund/reversal just because
    // its transactionStatus hasn't resolved yet. Both sides must carry
    // explicit, resolved, successful transaction semantics (never `null`/
    // unresolved), and the target itself must not be a settlement event
    // (refund/reversal) — a settlement's own resolved status can otherwise
    // happen to equal the candidate's (e.g. both `success` on differently
    // meant events), which is exactly the case this gate exists to catch.
    final targetIsSettlement =
        target.eventType == FinancialEventType.refund ||
        target.eventType == FinancialEventType.reversal ||
        targetStatus == TransactionStatus.refunded ||
        targetStatus == TransactionStatus.reversed;
    if (candidateMoved &&
        targetMoved &&
        !targetIsSettlement &&
        candidateStatus == TransactionStatus.success &&
        targetStatus == TransactionStatus.success) {
      return EventRelationshipType.duplicate;
    }

    return EventRelationshipType.relatedEvent;
  }

  String _reasonFor(EventRelationshipType type, EventRelationshipCandidate best) {
    switch (type) {
      case EventRelationshipType.duplicate:
        return 'Same underlying event, reported again with no status change.';
      case EventRelationshipType.update:
        return 'Same underlying event; status has changed since the last observation.';
      case EventRelationshipType.pendingUpdate:
        return 'Same underlying event; now pending.';
      case EventRelationshipType.failedUpdate:
        return 'Same underlying event; the attempt failed.';
      case EventRelationshipType.reversalOf:
        return 'Reverses an earlier matched charge.';
      case EventRelationshipType.refundOf:
        return 'Refunds an earlier matched charge.';
      case EventRelationshipType.reminderFor:
        return 'Resolves an earlier event that had not yet represented real money movement.';
      case EventRelationshipType.transferPair:
        return 'The other leg of a transfer between two of the user\'s own accounts.';
      default:
        return best.reason;
    }
  }

  EventRelationship _newEvent({required FinancialEvent candidate, required String id}) {
    return EventRelationship(
      id: id,
      sourceEventId: candidate.id,
      relationshipType: EventRelationshipType.newEvent,
      confidence: MatchConfidence.noMatch,
      score: 0,
      matchedSignals: const [],
      evidence: const [],
      reason: 'No related event found — treated as a new, standalone event.',
      needsReview: false,
      createdAt: candidate.eventDate,
    );
  }
}
