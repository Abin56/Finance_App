import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/soft_deletable_entity.dart';
import 'financial_event/transaction_status.dart';
import 'sms_candidate_cloud_identity.dart';
import 'sms_candidate_verification.dart';
import 'sms_confidence_scorer.dart';
import 'sms_direction_resolver.dart';
import 'sms_event_class.dart';
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
    required String cloudId,
    this.merchant,
    this.bankName,
    this.rawLastFour,
    this.accountId,
    this.cardId,
    this.referenceNumber,
    this.needsReviewReasons = const [],
    this.eventClass,
    this.moneyMovement,
    this.transactionStatus,
    this.directionEvidence,
    this.ownership,
    this.messageReceivedAt,
    this.dateSource,
    this.classificationVersion,
    // ignore: prefer_initializing_formals
  }) : _cloudId = cloudId;

  // --- Integrity fields (classification v1, 2026-11). All optional: a
  // document written before them simply lacks them, and FlowFi Web keeps its
  // earlier behaviour for such a document. See SmsCandidateVerification. ---

  /// What the message describes (`SmsEventClass.name`). Only a money-moving
  /// class may ever be imported.
  final SmsEventClass? eventClass;

  /// Whether money actually moved (derived from [eventClass]).
  final bool? moneyMovement;

  /// `TransactionStatus.name` read from the message (success/pending/…).
  final TransactionStatus? transactionStatus;

  /// `DirectionEvidence.name` — `contextual` (the message says whose
  /// account moved) or `keyword` (bare verbs only).
  final DirectionEvidence? directionEvidence;

  /// `SmsOwnership.name` — `verified` only when the last-4 resolved to one
  /// of the user's own accounts/cards on the phone.
  final SmsOwnership? ownership;

  /// When the SMS arrived — kept separately from [transactionDate], which
  /// may come from the date written in the message body ([dateSource]).
  final DateTime? messageReceivedAt;
  final SmsDateSource? dateSource;

  /// `kSmsCandidateClassificationVersion` at upload; a document with an
  /// older or missing value is refreshed by `SmsCandidateCloudSync`.
  final int? classificationVersion;

  /// Always `'sms'` — this collection is dedicated to SMS-derived candidates
  /// (see the collection-path comment in `firestore_constants.dart`), but
  /// carrying it as a literal field too is what Section 15 of the Web
  /// Transaction Studio spec asks for: a client merging documents from this
  /// collection with a future non-SMS one shouldn't have to infer origin
  /// from which collection a document came from.
  static const String source = 'sms';

  /// The `SmsInboxItem.id` (== `TransactionCandidate.smsItemId`) this was
  /// built from — the LOCAL join key back to the device's own
  /// `sms_inbox`/`sms_transaction_candidates` rows. No longer always the
  /// Firestore document id — see [id]/[cloudId] and
  /// `SmsCandidateCloudIdentity`'s doc comment (Phase F1, 2026-10-24).
  final String smsItemId;

  /// Computed once at construction via [SmsCandidateCloudIdentity.compute]
  /// — either a reference-number-derived, device-independent id (so the
  /// same eligible SMS captured on two devices maps to one Firestore
  /// document), or [smsItemId] itself as the conservative fallback when no
  /// reference number was parseable. Never recomputed from a decoded
  /// Firestore document (see [fromFirestore]): the document's own id, once
  /// written, IS the identity — recomputing it from possibly-absent stored
  /// fields would risk drifting from the id this document actually lives
  /// at.
  final String _cloudId;

  /// The Firestore document id — see [SoftDeletableEntity.id] and
  /// [_cloudId]'s doc comment for exactly how it's derived.
  @override
  String get id => _cloudId;

  /// Public alias for [id] — some call sites read cloud identity by this
  /// more specific name for clarity against [smsItemId].
  String get cloudId => _cloudId;

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
  /// [TransactionCandidate] plus the two extra inputs it doesn't carry:
  /// [rawLastFour] (sourced from the SMS parse directly) and [sender] (the
  /// raw SMS sender/address — needed only to compute [cloudId], never
  /// stored in the document itself; see the class doc for why no raw SMS
  /// data is persisted here).
  ///
  /// [verification] (from `SmsCandidateVerifier`, recomputed from the stored
  /// raw SMS at every sync) fills the integrity fields and overrides the
  /// stored review state and date, so a candidate built before those checks
  /// existed is still uploaded with current answers. Without it the
  /// document is legacy-shaped (no integrity fields).
  factory SmsTransactionCandidateCloud.fromLocal(
    TransactionCandidate candidate, {
    required String sender,
    String? rawLastFour,
    SmsCandidateVerification? verification,
  }) {
    final v = verification;
    final reasons = [
      ...candidate.reviewReasons,
      if (v != null)
        for (final r in v.reasons)
          if (!candidate.reviewReasons.contains(r)) r,
    ];
    return SmsTransactionCandidateCloud(
      smsItemId: candidate.smsItemId,
      cloudId: SmsCandidateCloudIdentity.compute(
        sender: sender,
        referenceNumber: candidate.referenceNumber,
        maskedAccountOrCard: rawLastFour,
        amount: candidate.amount,
        direction: candidate.direction,
        legacyPerDeviceId: candidate.smsItemId,
      ),
      amount: candidate.amount,
      direction: candidate.direction,
      eventType: candidate.eventType,
      transactionDate: v?.transactionDate ?? candidate.transactionDate,
      merchant: candidate.merchant,
      bankName: candidate.bankName,
      rawLastFour: rawLastFour,
      accountId: candidate.matchedAccountId,
      cardId: candidate.matchedCardId,
      referenceNumber: candidate.referenceNumber,
      confidenceLevel:
          v != null && !(v.moneyMovement && v.directionMatchesParse)
          ? ConfidenceLevel.low
          : candidate.confidenceLevel,
      confidenceScore: candidate.confidenceScore,
      needsReview: candidate.needsReview || (v != null && !v.cleanForImport),
      needsReviewReasons: reasons,
      createdAt: candidate.createdAt,
      eventClass: v?.eventClass,
      moneyMovement: v?.moneyMovement,
      transactionStatus: v?.transactionStatus,
      directionEvidence: v?.direction.evidence,
      ownership: v?.ownership,
      messageReceivedAt: v?.messageReceivedAt,
      dateSource: v?.dateSource,
      classificationVersion: v == null
          ? null
          : kSmsCandidateClassificationVersion,
    );
  }

  /// This document with [accountId]/[cardId] replaced — used when a refresh
  /// must keep a match the existing cloud document already has.
  SmsTransactionCandidateCloud withMatch({
    required String? accountId,
    required String? cardId,
  }) => SmsTransactionCandidateCloud(
    smsItemId: smsItemId,
    cloudId: _cloudId,
    amount: amount,
    direction: direction,
    eventType: eventType,
    transactionDate: transactionDate,
    merchant: merchant,
    bankName: bankName,
    rawLastFour: rawLastFour,
    accountId: accountId,
    cardId: cardId,
    referenceNumber: referenceNumber,
    confidenceLevel: confidenceLevel,
    confidenceScore: confidenceScore,
    needsReview: needsReview,
    needsReviewReasons: needsReviewReasons,
    createdAt: createdAt,
    eventClass: eventClass,
    moneyMovement: moneyMovement,
    transactionStatus: transactionStatus,
    directionEvidence: directionEvidence,
    ownership: accountId != null || cardId != null
        ? SmsOwnership.verified
        : ownership,
    messageReceivedAt: messageReceivedAt,
    dateSource: dateSource,
    classificationVersion: classificationVersion,
  );

  factory SmsTransactionCandidateCloud.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    final directionName = data['direction'] as String?;
    final direction = SmsTransactionDirectionX.fromName(directionName);
    if (direction == null) {
      throw StateError(
        'smsTransactionCandidates/${snapshot.id} has no valid direction',
      );
    }

    return SmsTransactionCandidateCloud(
      // The document's own id IS its identity, written once at upload time
      // by SmsCandidateCloudIdentity — never recomputed on read.
      cloudId: snapshot.id,
      // `smsItemId` is stored explicitly (see toFirestore) precisely
      // because, since Phase F1, it can differ from the document id —
      // `sync()` needs it to join this cloud row back to its local
      // `SmsInboxItem`/`TransactionCandidate` row. Falls back to the
      // document id for any pre-Phase-F1 document that predates the field
      // (where the two were always equal anyway).
      smsItemId: data['smsItemId'] as String? ?? snapshot.id,
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
      confidenceLevel: ConfidenceLevel.values.byName(
        data['confidenceLevel'] as String? ?? ConfidenceLevel.low.name,
      ),
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      needsReview: data['needsReview'] as bool? ?? true,
      needsReviewReasons:
          (data['needsReviewReasons'] as List<dynamic>? ?? const [])
              .cast<String>(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      eventClass: SmsEventClassX.fromName(data['eventClass'] as String?),
      moneyMovement: data['moneyMovement'] as bool?,
      transactionStatus: data['transactionStatus'] == null
          ? null
          : TransactionStatusX.fromName(data['transactionStatus'] as String?),
      directionEvidence: _byName(
        DirectionEvidence.values,
        data['directionEvidence'],
      ),
      ownership: _byName(SmsOwnership.values, data['ownership']),
      messageReceivedAt: (data['messageReceivedAt'] as Timestamp?)?.toDate(),
      dateSource: _byName(SmsDateSource.values, data['dateSource']),
      classificationVersion: (data['classificationVersion'] as num?)?.toInt(),
    )..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate();
  }

  static T? _byName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  Map<String, dynamic> toFirestore() {
    return {
      // Stored explicitly since Phase F1 (2026-10-24): the document id
      // ([id]/[cloudId]) can now differ from the local row id this
      // document was built from — see [smsItemId]'s doc comment.
      'smsItemId': smsItemId,
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
      // Integrity fields — written only when computed, so a legacy-shaped
      // document stays byte-for-byte what it was.
      if (eventClass != null) 'eventClass': eventClass!.name,
      if (moneyMovement != null) 'moneyMovement': moneyMovement,
      if (transactionStatus != null)
        'transactionStatus': transactionStatus!.name,
      if (directionEvidence != null)
        'directionEvidence': directionEvidence!.name,
      if (ownership != null) 'ownership': ownership!.name,
      if (messageReceivedAt != null)
        'messageReceivedAt': Timestamp.fromDate(messageReceivedAt!),
      if (dateSource != null) 'dateSource': dateSource!.name,
      if (classificationVersion != null)
        'classificationVersion': classificationVersion,
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
