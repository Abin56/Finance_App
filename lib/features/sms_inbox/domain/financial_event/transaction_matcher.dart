import '../../data/financial_event_dao.dart';
import 'financial_event.dart';
import 'financial_event_type.dart';

/// What `TransactionMatcher` decided about a freshly-extracted
/// [FinancialEvent] relative to events already stored.
enum FinancialEventMatchResult {
  /// No existing event matches — this candidate becomes a brand-new
  /// [FinancialEvent] row.
  newEvent,

  /// Another stored event already describes this same real-world
  /// transaction (matched by reference/UTR/RRN + amount) — this SMS becomes
  /// additional evidence linked to that event, not a new row.
  existingEvent,

  /// Reserved — no scenario this phase produces this result yet (see the
  /// SMS AI rebuild plan's deferred items). Kept in the enum so a future
  /// "this SMS corrects/completes an existing event" case is a new branch,
  /// not a breaking enum change.
  updateExisting,

  /// The AI flagged this as a likely refund and it matches an existing
  /// [FinancialEventRole.originalCharge] on amount/sender within a lookback
  /// window — becomes its own new event with
  /// [FinancialEventRole.linkedSettlement], not a mutation of the original.
  refundOfExisting,

  reversalOfExisting,

  /// A weak-signal match (same sender + amount within a short window, no
  /// reference number on either side to confirm) — always surfaced for
  /// manual review, never silently merged or discarded.
  possibleDuplicate,

  /// This candidate is a real money-movement event (`moneyMovement == true`)
  /// that resolves an earlier reminder or failed/pending attempt
  /// (`moneyMovement == false`) with the same sender and amount — e.g. "your
  /// EMI is due tomorrow" followed weeks later by "₹8,500 debited towards
  /// your EMI", or a failed UPI payment followed by a successful retry. The
  /// earlier event is left as-is (it's still real history); this candidate
  /// becomes its own new event linked to it, never a mutation.
  resolvesPriorEvent,
}

/// [TransactionMatcher]'s verdict, plus a human-readable justification —
/// same transparency principle every other matcher/scorer in this feature
/// already follows (see `AccountMatchResult.matchReason`,
/// `SmsDuplicateReason.explanation`).
class TransactionMatchOutcome {
  const TransactionMatchOutcome({
    required this.result,
    this.matchedEventId,
    required this.reason,
  });

  final FinancialEventMatchResult result;

  /// Set for every result except [FinancialEventMatchResult.newEvent].
  final String? matchedEventId;

  final String reason;
}

/// Decides whether a freshly-extracted [FinancialEvent] describes a
/// brand-new real-world transaction or one already known about — and, if
/// known, how it relates (additional evidence, refund, reversal, or a
/// possible duplicate).
///
/// Reference/UTR/RRN is the strongest signal (checked first) but never the
/// only one — sender+amount+time-window matching backs the cases where no
/// reference number is available, mirroring `SmsDedupKey`'s existing
/// two-tier design (`sameReferenceNumber` vs `sameSenderAmountAndTime`), but
/// resolving to a *shared event* rather than a flat duplicate-of-id chain
/// (see [SmsInboxDatabase.schemaVersion]'s v5 doc comment for why that
/// structurally fixes the old orphaned-duplicate bug).
class TransactionMatcher {
  const TransactionMatcher(this._dao);

  final FinancialEventDao _dao;

  /// How far back an AI-flagged refund/reversal is allowed to look for the
  /// original charge it resolves.
  static const _refundReversalWindow = Duration(days: 45);

  /// How close in time two same-sender, same-amount events must be to be
  /// treated as a possible duplicate rather than two coincidentally
  /// identical, genuinely separate transactions.
  static const _possibleDuplicateWindow = Duration(hours: 6);

  /// How far back a real transaction is allowed to look for an earlier
  /// reminder/failed/pending attempt it resolves — wider than
  /// [_possibleDuplicateWindow] since a bill reminder can precede its actual
  /// payment by weeks, and a failed-then-retried payment is often same-day
  /// but sometimes days later.
  static const _priorEventWindow = Duration(days: 60);

  Future<TransactionMatchOutcome> match(
    FinancialEvent candidate, {
    bool isLikelyRefundOrReversal = false,
  }) async {
    final referenceMatch = await _matchByReference(candidate);
    if (referenceMatch != null) return referenceMatch;

    final refundMatch = await _matchRefundOrReversal(
      candidate,
      isLikelyRefundOrReversal: isLikelyRefundOrReversal,
    );
    if (refundMatch != null) return refundMatch;

    // A candidate that is itself not a real money movement (a reminder, a
    // failed/pending attempt) has nothing to dedupe against in the normal
    // sense — it always becomes its own new (informational) event, and it's
    // the *later* real transaction that looks backward to find and link it
    // (see _matchResolvesPriorEvent, called for that later candidate).
    if (candidate.moneyMovement.value == true) {
      final priorMatch = await _matchResolvesPriorEvent(candidate);
      if (priorMatch != null) return priorMatch;

      final weakMatch = await _matchWeakSignal(candidate);
      if (weakMatch != null) return weakMatch;
    }

    return const TransactionMatchOutcome(
      result: FinancialEventMatchResult.newEvent,
      reason: 'No matching existing event found.',
    );
  }

  Future<TransactionMatchOutcome?> _matchByReference(
    FinancialEvent candidate,
  ) async {
    final referenceNumber = candidate.referenceNumber;
    if (referenceNumber == null || referenceNumber.isEmpty) return null;

    final matches = await _dao.findByReferenceNumber(referenceNumber);
    if (matches.isEmpty) return null;

    final candidateAmount = candidate.amount.value;
    final sameAmount = candidateAmount == null
        ? const <FinancialEvent>[]
        : matches
              .where(
                (m) =>
                    m.amount.value != null &&
                    (m.amount.value! - candidateAmount).abs() < 0.01,
              )
              .toList();

    if (sameAmount.isNotEmpty) {
      return TransactionMatchOutcome(
        result: FinancialEventMatchResult.existingEvent,
        matchedEventId: sameAmount.first.id,
        reason:
            'Same reference number ($referenceNumber) and amount as an existing event.',
      );
    }

    // Same reference, different amount — a genuine identity signal that
    // still disagrees on amount is exactly the case that must be surfaced,
    // never silently resolved either way.
    return TransactionMatchOutcome(
      result: FinancialEventMatchResult.possibleDuplicate,
      matchedEventId: matches.first.id,
      reason:
          'Same reference number ($referenceNumber) as an existing event, but a different amount — please confirm.',
    );
  }

  Future<TransactionMatchOutcome?> _matchRefundOrReversal(
    FinancialEvent candidate, {
    required bool isLikelyRefundOrReversal,
  }) async {
    if (!isLikelyRefundOrReversal) return null;
    final sender = candidate.normalizedSender;
    final amount = candidate.amount.value;
    if (sender == null || amount == null) return null;

    final originals = await _dao.findOriginalChargesInWindow(
      normalizedSender: sender,
      start: candidate.eventDate.subtract(_refundReversalWindow),
      end: candidate.eventDate,
    );
    final amountMatch = originals
        .where(
          (o) =>
              o.amount.value != null && (o.amount.value! - amount).abs() < 0.01,
        )
        .toList();
    if (amountMatch.isEmpty) return null;

    final original = amountMatch.first;
    final isReversal = candidate.eventType == FinancialEventType.reversal;
    return TransactionMatchOutcome(
      result: isReversal
          ? FinancialEventMatchResult.reversalOfExisting
          : FinancialEventMatchResult.refundOfExisting,
      matchedEventId: original.id,
      reason: isReversal
          ? 'AI flagged this as a likely reversal of an earlier charge with the same sender and amount.'
          : 'AI flagged this as a likely refund of an earlier charge with the same sender and amount.',
    );
  }

  /// A real transaction (this method only ever runs when
  /// `candidate.moneyMovement.value == true`, see [match]) that shares a
  /// sender and amount with an earlier reminder/failed/pending event — the
  /// most recent such prior event within [_priorEventWindow] is treated as
  /// what this transaction resolves. The earlier event is left untouched;
  /// this candidate becomes its own new event, linked to it (never a
  /// mutation — see [FinancialEventMatchResult.resolvesPriorEvent]'s doc).
  Future<TransactionMatchOutcome?> _matchResolvesPriorEvent(
    FinancialEvent candidate,
  ) async {
    final sender = candidate.normalizedSender;
    final amount = candidate.amount.value;
    if (sender == null || amount == null) return null;

    final siblings = await _dao.findBySenderAmountWindow(
      normalizedSender: sender,
      amount: amount,
      start: candidate.eventDate.subtract(_priorEventWindow),
      end: candidate.eventDate,
    );
    final nonMovement =
        siblings.where((e) => e.moneyMovement.value == false).toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
    if (nonMovement.isEmpty) return null;

    final prior = nonMovement.first;
    return TransactionMatchOutcome(
      result: FinancialEventMatchResult.resolvesPriorEvent,
      matchedEventId: prior.id,
      reason:
          'Resolves an earlier ${prior.eventType.label.toLowerCase()} with the same sender and amount.',
    );
  }

  /// Only ever runs for a real-money-movement candidate against other
  /// real-money-movement events (see [match]) — a reminder or a failed
  /// attempt sharing a sender/amount with a genuine transaction is not "a
  /// possible duplicate" of it, it's the separate case
  /// [_matchResolvesPriorEvent] already handles.
  Future<TransactionMatchOutcome?> _matchWeakSignal(
    FinancialEvent candidate,
  ) async {
    final sender = candidate.normalizedSender;
    final amount = candidate.amount.value;
    if (sender == null || amount == null) return null;

    final siblings = await _dao.findBySenderAmountWindow(
      normalizedSender: sender,
      amount: amount,
      start: candidate.eventDate.subtract(_possibleDuplicateWindow),
      end: candidate.eventDate.add(_possibleDuplicateWindow),
    );
    final movementSiblings = siblings
        .where((e) => e.moneyMovement.value == true)
        .toList();
    if (movementSiblings.isEmpty) return null;

    return TransactionMatchOutcome(
      result: FinancialEventMatchResult.possibleDuplicate,
      matchedEventId: movementSiblings.first.id,
      reason:
          'Same sender and amount as an existing event within a few hours, with no reference number to confirm either way.',
    );
  }
}
