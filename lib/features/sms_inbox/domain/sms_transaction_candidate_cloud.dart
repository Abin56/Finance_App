import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/soft_deletable_entity.dart';
import 'sms_confidence_scorer.dart';
import 'sms_transaction_category.dart';
import 'sms_transaction_direction.dart';
import 'transaction_candidate.dart';

/// The minimal, structured cloud representation of a `TransactionCandidate`
/// — everything the future Web Transaction Studio needs to display and
/// review one SMS-detected transaction, and nothing else.
///
/// What this deliberately does NOT carry, and why:
///  - No raw SMS body/sender — the whole point of this collection existing
///    is that it's safe to sync; the message itself never leaves the device.
///  - No full account/card number, PIN, or CVV — only [accountId]/[cardId]
///    (pointers into the user's own already-synced `accounts`/`creditCards`
///    collections) and, when unresolved, [rawLastFour] — 4 digits only, the
///    same masking the local `sms_inbox` table already applies.
///  - No `userId` field — the Firestore path itself
///    (`users/{uid}/smsTransactionCandidates/{id}`) is the scope; no other
///    entity in this app duplicates its own owner id into the document body.
///  - No `categoryId` — Phase 1 deliberately never resolves a FlowFi
///    category at candidate-build time (only at conversion time, via
///    `MerchantCategorySuggester`); inventing one here would be a second,
///    earlier, and inconsistent category-suggestion path.
///  - No `candidateStatus` — seeding this field would create a second
///    lifecycle competing with `SmsInboxItem.status`, exactly what Phase 1
///    already avoided locally. Status is instead *derived from document
///    existence*: `SmsCandidateCloudSync` only keeps a cloud document for
///    an SMS that is still pending and non-duplicate locally, and deletes
///    it the moment that stops being true. A row existing here always means
///    "still awaiting review or conversion."
///  - No `updatedAt` — every write is a full, idempotent overwrite of an
///    immutable-in-practice snapshot (Phase 1 never regenerates a candidate
///    for an SMS that already has one), so there is no partial-update
///    history worth tracking separately from [createdAt].
class SmsTransactionCandidateCloud extends SoftDeletableEntity {
  SmsTransactionCandidateCloud({
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
    this.rawLastFour,
    this.accountId,
    this.cardId,
    this.referenceNumber,
    this.needsReviewReasons = const [],
  });

  /// Always `'sms'` — this collection is dedicated to SMS-derived candidates
  /// (see the collection-path comment in `firestore_constants.dart`), but
  /// carrying it as a literal field too is what Section 15 of the Web
  /// Transaction Studio spec asks for: a client merging documents from this
  /// collection with a future non-SMS one shouldn't have to infer origin
  /// from which collection a document came from.
  static const String source = 'sms';

  /// The `SmsInboxItem.id` (== `TransactionCandidate.smsItemId`) this was
  /// built from — also the Firestore document id, which is what makes
  /// re-syncing the same SMS an idempotent overwrite rather than a
  /// duplicate. See [SoftDeletableEntity.id].
  final String smsItemId;

  @override
  String get id => smsItemId;

  final double amount;
  final SmsTransactionDirection direction;

  /// Reuses `SmsTransactionCategory` — Phase 1's deliberate choice not to
  /// invent a second `TransactionEventType` taxonomy, carried through here
  /// unchanged. See that enum's doc for the full value set.
  final SmsTransactionCategory eventType;

  final DateTime transactionDate;
  final String? merchant;
  final String? bankName;

  /// The last-4 digits the SMS itself exposed (`ParsedSmsTransaction.maskedAccountOrCard`),
  /// independent of whether [accountId]/[cardId] resolved. Kept even when an
  /// account *was* matched (so the web UI has it without a second read), and
  /// especially important when nothing matched: it is the only hint a human
  /// reviewer has to resolve the account manually. Never more than 4 digits —
  /// this is exactly what the local SMS parser already extracts and stores,
  /// never a full account/card number.
  final String? rawLastFour;

  /// Matches an existing `Account.id`. Null means [AccountCardMatcher]
  /// could not confidently resolve one — never a guess.
  final String? accountId;

  /// Matches an existing `CreditCardProfile.id`, set only alongside
  /// [accountId] when the match was a credit card.
  final String? cardId;

  final String? referenceNumber;

  /// High/Medium/Low — the exact verdict `SmsConfidenceScorer` produced
  /// locally, not recomputed here.
  final ConfidenceLevel confidenceLevel;
  final double confidenceScore;

  final bool needsReview;
  final List<String> needsReviewReasons;

  final DateTime createdAt;

  /// Builds the cloud document from the already-computed local
  /// [TransactionCandidate] plus the one extra field it doesn't carry
  /// ([rawLastFour], sourced from the SMS parse directly) — see the class
  /// doc for why nothing else is added.
  factory SmsTransactionCandidateCloud.fromLocal(TransactionCandidate candidate, {String? rawLastFour}) {
    return SmsTransactionCandidateCloud(
      smsItemId: candidate.smsItemId,
      amount: candidate.amount,
      direction: candidate.direction,
      eventType: candidate.eventType,
      transactionDate: candidate.transactionDate,
      merchant: candidate.merchant,
      bankName: candidate.bankName,
      rawLastFour: rawLastFour,
      accountId: candidate.matchedAccountId,
      cardId: candidate.matchedCardId,
      referenceNumber: candidate.referenceNumber,
      confidenceLevel: candidate.confidenceLevel,
      confidenceScore: candidate.confidenceScore,
      needsReview: candidate.needsReview,
      needsReviewReasons: candidate.reviewReasons,
      createdAt: candidate.createdAt,
    );
  }

  factory SmsTransactionCandidateCloud.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    final directionName = data['direction'] as String?;
    final direction = SmsTransactionDirectionX.fromName(directionName);
    if (direction == null) {
      throw StateError('smsTransactionCandidates/${snapshot.id} has no valid direction');
    }

    return SmsTransactionCandidateCloud(
      smsItemId: snapshot.id,
      amount: (data['amount'] as num).toDouble(),
      direction: direction,
      eventType: SmsTransactionCategoryX.fromName(data['eventType'] as String?),
      transactionDate: (data['transactionDate'] as Timestamp).toDate(),
      merchant: data['merchant'] as String?,
      bankName: data['bankName'] as String?,
      rawLastFour: data['rawLastFour'] as String?,
      accountId: data['accountId'] as String?,
      cardId: data['cardId'] as String?,
      referenceNumber: data['referenceNumber'] as String?,
      confidenceLevel: ConfidenceLevel.values.byName(data['confidenceLevel'] as String? ?? ConfidenceLevel.low.name),
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      needsReview: data['needsReview'] as bool? ?? true,
      needsReviewReasons: (data['needsReviewReasons'] as List<dynamic>? ?? const []).cast<String>(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    )..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'direction': direction.name,
      'eventType': eventType.name,
      'transactionDate': Timestamp.fromDate(transactionDate),
      'merchant': merchant,
      'bankName': bankName,
      'rawLastFour': rawLastFour,
      'accountId': accountId,
      'cardId': cardId,
      'referenceNumber': referenceNumber,
      'confidenceLevel': confidenceLevel.name,
      'confidenceScore': confidenceScore,
      'needsReview': needsReview,
      'needsReviewReasons': needsReviewReasons,
      'source': source,
      'createdAt': Timestamp.fromDate(createdAt),
      // Written explicitly (rather than omitted) because
      // `FirestoreCrudRepository.getAll/watchAll` filter on
      // `where('deletedAt', isNull: true)` — a Firestore equality query
      // against `null` only matches documents where the field is present
      // and null, never documents where the field is simply absent. This
      // entity is never actually soft-deleted (`SmsCandidateCloudSync` hard
      // -deletes via `permanentlyDelete`/`deleteById` instead), so the
      // value is always null — but it must still be written.
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
    };
  }
}
