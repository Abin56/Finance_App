import '../financial_event/financial_event.dart';
import 'event_relationship.dart';
import 'event_relationship_lookup.dart';
import 'event_relationship_type.dart';
import 'match_confidence.dart';
import 'matching_signal.dart';

/// Pairs the debit and credit halves of one transfer between two of the
/// user's own accounts — Part 10 of the task.
///
/// Deliberately narrow: only ever runs on a [FinancialEvent] the existing
/// (owned) extractor has already flagged `isOwnAccountTransfer == true` —
/// that flag is set purely deterministically, from the message's own text
/// naming a second last-4 that matches one of the user's other accounts
/// (see `AccountCardMatcher.isKnownLastFour`'s doc comment). This detector
/// never re-derives "is this a transfer" itself; it only tries to find the
/// other SMS describing the opposite leg, so neither side is ever
/// double-counted as income and an expense (Safety rules 6-7).
///
/// If no counterpart SMS has been observed yet, the transfer is left as a
/// single, unresolved leg — never silently treated as ordinary income or
/// an ordinary expense (Part 10: "If only one side is available, keep it
/// as an own-account transfer event with unresolved counterpart side").
class TransferPairDetector {
  const TransferPairDetector(this._lookup);

  final EventRelationshipLookup _lookup;

  static const _defaultWindow = Duration(hours: 6);

  /// Returns `null` when [candidate] is not itself flagged as an
  /// own-account transfer — nothing for this detector to do.
  Future<EventRelationship?> detect({
    required FinancialEvent candidate,
    required String id,
    Duration window = _defaultWindow,
  }) async {
    if (!candidate.isOwnAccountTransfer) return null;
    final amount = candidate.amount.value;
    if (amount == null) {
      return EventRelationship(
        id: id,
        sourceEventId: candidate.id,
        relationshipType: EventRelationshipType.unknownRelationship,
        confidence: MatchConfidence.noMatch,
        score: 0,
        matchedSignals: const [],
        evidence: const [],
        reason:
            'Flagged as an own-account transfer, but no amount was resolved — cannot search for the counterpart leg.',
        needsReview: true,
        createdAt: candidate.eventDate,
      );
    }

    final candidates = await _lookup.findOwnAccountTransferCandidates(
      amount: amount,
      start: candidate.eventDate.subtract(window),
      end: candidate.eventDate.add(window),
      excludeEventId: candidate.id,
    );

    final opposite = candidates
        .where(
          (e) =>
              e.direction != candidate.direction &&
              (candidate.accountMatch.value == null ||
                  e.accountMatch.value == null ||
                  candidate.accountMatch.value != e.accountMatch.value),
        )
        .toList();

    if (opposite.isEmpty) {
      return EventRelationship(
        id: id,
        sourceEventId: candidate.id,
        relationshipType: EventRelationshipType.unknownRelationship,
        confidence: MatchConfidence.noMatch,
        score: 0,
        matchedSignals: const [],
        evidence: const [],
        reason:
            'Own-account transfer with no counterpart SMS found yet — kept as an unresolved transfer, never treated as income or an expense.',
        needsReview: true,
        createdAt: candidate.eventDate,
      );
    }

    if (opposite.length > 1) {
      final candidateSummaries = opposite
          .map(
            (e) => EventRelationshipCandidate(
              targetEventId: e.id,
              score: 0,
              confidence: MatchConfidence.medium,
              matchedSignals: const [
                MatchedSignal(
                  signal: MatchingSignal.amount,
                  weight: 0,
                  description: 'Same amount, opposite direction, own-account flagged.',
                ),
              ],
              reason: 'Candidate counterpart leg: event ${e.id}.',
            ),
          )
          .toList();
      return EventRelationship(
        id: id,
        sourceEventId: candidate.id,
        relationshipType: EventRelationshipType.possibleMatch,
        confidence: MatchConfidence.medium,
        score: 0,
        matchedSignals: const [],
        evidence: candidateSummaries.map((c) => c.reason).toList(),
        reason:
            'Multiple candidate counterpart legs found for this own-account transfer — surfaced for manual confirmation rather than auto-paired.',
        needsReview: true,
        createdAt: candidate.eventDate,
        alternativeCandidates: candidateSummaries,
      );
    }

    final match = opposite.single;
    return EventRelationship(
      id: id,
      sourceEventId: candidate.id,
      targetEventId: match.id,
      relationshipType: EventRelationshipType.transferPair,
      confidence: MatchConfidence.high,
      score: 100,
      matchedSignals: const [
        MatchedSignal(
          signal: MatchingSignal.amount,
          weight: 0,
          description: 'Same amount, opposite direction, both own-account flagged.',
        ),
      ],
      evidence: [
        'Same amount (₹$amount), opposite direction, both flagged as own-account transfer, within the lookback window.',
      ],
      reason:
          'The other leg of this transfer between the user\'s own accounts.',
      needsReview: false,
      createdAt: candidate.eventDate,
    );
  }
}
