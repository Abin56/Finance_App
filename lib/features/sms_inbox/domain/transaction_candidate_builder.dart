import '../../../core/utils/id_generator.dart';
import 'account_card_matcher.dart';
import 'sms_candidate_verification.dart';
import 'sms_confidence_scorer.dart';
import 'sms_inbox_item.dart';
import 'transaction_candidate.dart';

/// Builds a [TransactionCandidate] for one already-parsed [SmsInboxItem],
/// composing [AccountCardMatcher] and [SmsConfidenceScorer] — the only place
/// those two are wired together, so any future caller (a bulk backfill, a
/// test) never has to re-derive this sequence itself.
class TransactionCandidateBuilder {
  const TransactionCandidateBuilder(
    this._matcher, {
    this.scorer = const SmsConfidenceScorer(),
  });

  final AccountCardMatcher _matcher;
  final SmsConfidenceScorer scorer;

  /// Returns null for an item with no [SmsInboxItem.parsed] result — there is
  /// nothing to build a candidate from (no amount/direction/category), same
  /// as the SMS Inbox UI already treats an unparsed item: shown for manual
  /// review with every field blank, never auto-processed.
  TransactionCandidate? build(SmsInboxItem item) {
    final parsed = item.parsed;
    if (parsed == null) return null;

    final accountMatch = _matcher.match(parsed);
    final confidence = scorer.score(
      parsed: parsed,
      accountMatch: accountMatch,
      isDuplicate: item.isDuplicate,
    );
    // The integrity checks (direction from context, real money movement,
    // ownership, transaction date) — see SmsCandidateVerifier. Folded into
    // the existing review fields so every consumer, local or web, sees them.
    final verification = SmsCandidateVerifier.verify(
      body: item.rawMessage.body,
      receivedAt: item.rawMessage.date,
      parsedDirection: parsed.direction,
      accountResolved: accountMatch.isResolved,
      matchedCardId: accountMatch.matchedCardId,
    );
    final reasons = [
      ...confidence.reasons,
      for (final r in verification.reasons)
        if (!confidence.reasons.contains(r)) r,
    ];
    // "High confidence" is never shown for something that isn't a verified
    // money movement.
    final level =
        verification.moneyMovement && verification.directionMatchesParse
        ? confidence.level
        : ConfidenceLevel.low;

    return TransactionCandidate(
      id: IdGenerator.generate(),
      smsItemId: item.id,
      amount: parsed.amount,
      direction: parsed.direction,
      eventType: parsed.category,
      transactionDate: verification.transactionDate,
      merchant: parsed.merchantOrSender,
      bankName: parsed.bankName,
      matchedAccountId: accountMatch.matchedAccountId,
      matchedCardId: accountMatch.matchedCardId,
      referenceNumber: parsed.referenceNumber,
      confidenceLevel: level,
      confidenceScore: confidence.score,
      needsReview: confidence.needsReview || !verification.cleanForImport,
      reviewReasons: reasons,
      createdAt: DateTime.now(),
    );
  }
}
