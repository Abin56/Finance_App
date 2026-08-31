import '../../../core/utils/id_generator.dart';
import 'account_card_matcher.dart';
import 'sms_confidence_scorer.dart';
import 'sms_inbox_item.dart';
import 'transaction_candidate.dart';

/// Builds a [TransactionCandidate] for one already-parsed [SmsInboxItem],
/// composing [AccountCardMatcher] and [SmsConfidenceScorer] — the only place
/// those two are wired together, so any future caller (a bulk backfill, a
/// test) never has to re-derive this sequence itself.
class TransactionCandidateBuilder {
  const TransactionCandidateBuilder(this._matcher, {this.scorer = const SmsConfidenceScorer()});

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
    final confidence = scorer.score(parsed: parsed, accountMatch: accountMatch, isDuplicate: item.isDuplicate);

    return TransactionCandidate(
      id: IdGenerator.generate(),
      smsItemId: item.id,
      amount: parsed.amount,
      direction: parsed.direction,
      eventType: parsed.category,
      transactionDate: parsed.dateTime,
      merchant: parsed.merchantOrSender,
      bankName: parsed.bankName,
      matchedAccountId: accountMatch.matchedAccountId,
      matchedCardId: accountMatch.matchedCardId,
      referenceNumber: parsed.referenceNumber,
      confidenceLevel: confidence.level,
      confidenceScore: confidence.score,
      needsReview: confidence.needsReview,
      reviewReasons: confidence.reasons,
      createdAt: DateTime.now(),
    );
  }
}
