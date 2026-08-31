import 'sms_confidence_scorer.dart';
import 'sms_transaction_category.dart';
import 'sms_transaction_direction.dart';

/// The structured middle layer between a raw [ParsedSmsTransaction]
/// (`parsed_sms_transaction.dart`) and a real, Firestore-backed
/// `Transaction` — produced by `TransactionCandidateBuilder` for every
/// parsed, non-ignored [SmsInboxItem] and persisted locally alongside it
/// (see `TransactionCandidateDao`), never in Firestore.
///
/// Deliberately does not duplicate state that already lives elsewhere:
/// - No `source` field — this table only ever holds SMS-derived candidates,
///   so "source" is the table itself, not a per-row value.
/// - No `status` field — [SmsInboxItem.status] (pending/imported/ignored)
///   remains the single source of truth for where a message is in the
///   review pipeline; this row is a companion, not a competing state
///   machine.
/// - No duplicate-of-id — [SmsInboxItem.duplicateOfId]/`duplicateReason`
///   already own that; a candidate for a duplicate message simply carries
///   "possible duplicate" in [reviewReasons] via the confidence scorer.
class TransactionCandidate {
  const TransactionCandidate({
    required this.id,
    required this.smsItemId,
    required this.amount,
    required this.direction,
    required this.eventType,
    required this.transactionDate,
    required this.confidenceLevel,
    required this.confidenceScore,
    required this.needsReview,
    required this.createdAt,
    this.merchant,
    this.bankName,
    this.matchedAccountId,
    this.matchedCardId,
    this.referenceNumber,
    this.reviewReasons = const [],
  });

  final String id;

  /// The [SmsInboxItem.id] this candidate was built from — the join key for
  /// everything the SMS side already knows (raw body, dedup/duplicate state,
  /// import status).
  final String smsItemId;

  final double amount;
  final SmsTransactionDirection direction;

  /// The real-world event this SMS appears to describe — reuses
  /// [SmsTransactionCategory] (already produced by every `SmsParser` via
  /// `SmsRegexUtils.guessCategory`) rather than a second, parallel
  /// "transaction type" taxonomy.
  final SmsTransactionCategory eventType;

  final DateTime transactionDate;
  final String? merchant;
  final String? bankName;

  /// Set when [AccountCardMatcher] confidently resolved an existing
  /// `Account`. Null means unresolved — see [needsReview].
  final String? matchedAccountId;

  /// Set only when the resolved account is a credit card.
  final String? matchedCardId;

  final String? referenceNumber;

  final ConfidenceLevel confidenceLevel;
  final double confidenceScore;

  /// True whenever this candidate should not be converted without a human
  /// looking at it first — see [SmsConfidenceResult.needsReview].
  final bool needsReview;

  /// Human-readable reasons behind [needsReview] (or, even when not needing
  /// review, minor caveats) — shown verbatim to the user, same transparency
  /// principle as [SmsConfidenceResult.reasons].
  final List<String> reviewReasons;

  final DateTime createdAt;
}
