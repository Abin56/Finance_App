import 'package:sqflite/sqflite.dart';

import '../domain/financial_event/automation_action.dart';
import '../domain/financial_event/field_confidence.dart';
import '../domain/financial_event/financial_event.dart';
import '../domain/financial_event/financial_event_evidence_link.dart';
import '../domain/financial_event/financial_event_role.dart';
import '../domain/financial_event/financial_event_status.dart';
import '../domain/financial_event/financial_event_type.dart';
import '../domain/financial_event/merchant_type.dart';
import '../domain/financial_event/payment_method.dart';
import '../domain/financial_event/payment_provider.dart';
import '../domain/financial_event/transaction_status.dart';
import '../domain/sms_confidence_scorer.dart';
import '../domain/sms_transaction_direction.dart';
import 'sms_inbox_database.dart';

/// Thin sqflite CRUD over `financial_events`/`sms_financial_event_links` —
/// mirrors [SmsInboxDao]/[TransactionCandidateDao]'s persistence-only role.
/// Matching/reconciliation logic lives in `TransactionMatcher`/
/// `FinancialEventExtractor`, not here.
class FinancialEventDao {
  const FinancialEventDao(this._db);

  final SmsInboxDatabase _db;

  Database get _database => _db.database;

  /// Reasons are free-text sentences that never contain this control
  /// character — same convention [TransactionCandidateDao] already uses.
  static const String _reasonSeparator = '';

  /// Upserts one event. Used both for a brand-new event and for bumping an
  /// existing one's confidence when [TransactionMatcher] finds additional
  /// corroborating evidence (see `FinancialEventLinkType.additionalEvidence`).
  Future<void> upsert(FinancialEvent event) async {
    await _database.insert(
      SmsInboxDatabase.financialEventsTableName,
      _toRow(event),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<FinancialEvent>> getAll() async {
    final rows = await _database.query(
      SmsInboxDatabase.financialEventsTableName,
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<FinancialEvent?> getById(String id) async {
    final rows = await _database.query(
      SmsInboxDatabase.financialEventsTableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Existing events sharing [referenceNumber] — the strongest identity
  /// signal `TransactionMatcher` checks first. Empty [referenceNumber]
  /// values are never stored as `''`, only `NULL`, so this never
  /// accidentally matches every reference-less event against each other.
  Future<List<FinancialEvent>> findByReferenceNumber(
    String referenceNumber,
  ) async {
    final rows = await _database.query(
      SmsInboxDatabase.financialEventsTableName,
      where: 'reference_number = ?',
      whereArgs: [referenceNumber],
    );
    return rows.map(_fromRow).toList();
  }

  /// Existing events from the same [normalizedSender] with the same [amount]
  /// whose [FinancialEvent.eventDate] falls within [start, end] — the weak
  /// signal behind `FinancialEventMatchResult.possibleDuplicate` /
  /// `.refundOfExisting` / `.reversalOfExisting` when no reference number is
  /// available to confirm identity.
  Future<List<FinancialEvent>> findBySenderAmountWindow({
    required String normalizedSender,
    required double amount,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _database.query(
      SmsInboxDatabase.financialEventsTableName,
      where:
          'normalized_sender = ? AND amount = ? AND event_date BETWEEN ? AND ?',
      whereArgs: [
        normalizedSender,
        amount,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    );
    return rows.map(_fromRow).toList();
  }

  /// Events with [FinancialEventRole.originalCharge] from the same
  /// [normalizedSender] within [start, end] — the candidate pool
  /// `TransactionMatcher` checks an AI-flagged refund/reversal against.
  Future<List<FinancialEvent>> findOriginalChargesInWindow({
    required String normalizedSender,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _database.query(
      SmsInboxDatabase.financialEventsTableName,
      where:
          'normalized_sender = ? AND role = ? AND event_date BETWEEN ? AND ?',
      whereArgs: [
        normalizedSender,
        FinancialEventRole.originalCharge.name,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> linkSms(FinancialEventEvidenceLink link) async {
    await _database.insert(
      SmsInboxDatabase.smsFinancialEventLinksTableName,
      {
        'id': link.id,
        'financial_event_id': link.financialEventId,
        'sms_item_id': link.smsItemId,
        'link_type': link.linkType.name,
        'confidence': link.confidence,
        'linked_at': link.linkedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<FinancialEventEvidenceLink>> getLinksForEvent(
    String financialEventId,
  ) async {
    final rows = await _database.query(
      SmsInboxDatabase.smsFinancialEventLinksTableName,
      where: 'financial_event_id = ?',
      whereArgs: [financialEventId],
      orderBy: 'linked_at ASC',
    );
    return rows.map(_linkFromRow).toList();
  }

  Future<FinancialEventEvidenceLink?> getLinkForSms(String smsItemId) async {
    final rows = await _database.query(
      SmsInboxDatabase.smsFinancialEventLinksTableName,
      where: 'sms_item_id = ?',
      whereArgs: [smsItemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _linkFromRow(rows.first);
  }

  /// The [FinancialEvent] linked to [smsItemId], if any — one query instead
  /// of a link lookup followed by a separate event lookup, for the UI's
  /// per-message summary display.
  Future<FinancialEvent?> getEventForSmsItem(String smsItemId) async {
    final link = await getLinkForSms(smsItemId);
    if (link == null) return null;
    return getById(link.financialEventId);
  }

  /// Every `sms_item_id` that already has a link row — generation skips
  /// these rather than re-processing an already-linked message on every
  /// scan, mirroring [TransactionCandidateDao.existingSmsItemIds].
  Future<Set<String>> smsItemIdsWithLinks() async {
    final rows = await _database.query(
      SmsInboxDatabase.smsFinancialEventLinksTableName,
      columns: ['sms_item_id'],
    );
    return rows.map((row) => row['sms_item_id']! as String).toSet();
  }

  /// Removes link rows for deleted SMS — called alongside
  /// [SmsInboxDao.deleteByIds]/[TransactionCandidateDao.deleteBySmsItemIds].
  /// Deliberately does **not** delete the [FinancialEvent] itself, even if
  /// this was its only remaining link: the event describes a real-world
  /// transaction that still happened, and any `linkedTransactionId` the user
  /// already converted it into must not be orphaned by a later SMS cleanup.
  /// This is exactly what structurally fixes the old orphaned-duplicate bug
  /// — see [SmsInboxDatabase.schemaVersion]'s v5 doc comment.
  Future<void> deleteLinksForSmsIds(List<String> smsItemIds) async {
    if (smsItemIds.isEmpty) return;
    final placeholders = List.filled(smsItemIds.length, '?').join(',');
    await _database.delete(
      SmsInboxDatabase.smsFinancialEventLinksTableName,
      where: 'sms_item_id IN ($placeholders)',
      whereArgs: smsItemIds,
    );
  }

  Map<String, Object?> _toRow(FinancialEvent event) {
    return {
      'id': event.id,
      'primary_sms_item_id': event.primarySmsItemId,
      'event_type': event.eventType.name,
      'role': event.role.name,
      'status': event.status.name,
      'direction': event.direction.name,
      'normalized_sender': event.normalizedSender,
      'amount': event.amount.value,
      'amount_confidence': event.amount.confidence,
      'amount_source': event.amount.source.name,
      'amount_ai_evidence': event.amount.aiEvidence,
      'amount_regex_evidence': event.amount.regexEvidence,
      'merchant': event.merchant.value,
      'merchant_confidence': event.merchant.confidence,
      'merchant_source': event.merchant.source.name,
      'merchant_ai_evidence': event.merchant.aiEvidence,
      'merchant_regex_evidence': event.merchant.regexEvidence,
      'category_id': event.category.value,
      'category_confidence': event.category.confidence,
      'category_source': event.category.source.name,
      'subcategory': event.subcategory,
      'payment_method': event.paymentMethod.value?.name,
      'payment_method_confidence': event.paymentMethod.confidence,
      'payment_method_source': event.paymentMethod.source.name,
      'matched_account_id': event.accountMatch.value,
      'matched_card_id': event.matchedCardId,
      'account_confidence': event.accountMatch.confidence,
      'account_source': event.accountMatch.source.name,
      'money_movement_value': switch (event.moneyMovement.value) {
        true => 1,
        false => 0,
        null => null,
      },
      'money_movement_confidence': event.moneyMovement.confidence,
      'money_movement_source': event.moneyMovement.source.name,
      'money_movement_regex_evidence': event.moneyMovement.regexEvidence,
      'transaction_status_value': event.transactionStatus.value?.name,
      'transaction_status_confidence': event.transactionStatus.confidence,
      'transaction_status_source': event.transactionStatus.source.name,
      'is_own_account_transfer': event.isOwnAccountTransfer ? 1 : 0,
      'payment_provider_value': event.paymentProvider.value?.name,
      'payment_provider_confidence': event.paymentProvider.confidence,
      'payment_provider_source': event.paymentProvider.source.name,
      'merchant_type_value': event.merchantType.value?.name,
      'merchant_type_confidence': event.merchantType.confidence,
      'merchant_type_source': event.merchantType.source.name,
      'merchant_type_evidence': event.merchantType.regexEvidence,
      'event_date': event.eventDate.millisecondsSinceEpoch,
      'overall_confidence': event.overallConfidence,
      'confidence_level': event.confidenceLevel.name,
      'automation_action': event.automationAction.name,
      'needs_review': event.needsReview ? 1 : 0,
      'review_reasons': event.reviewReasons.isEmpty
          ? null
          : event.reviewReasons.join(_reasonSeparator),
      'reference_number': event.referenceNumber,
      'linked_transaction_id': event.linkedTransactionId,
      'linked_event_id': event.linkedEventId,
      'ai_raw_response': event.aiRawResponse,
      'ai_model_version': event.aiModelVersion,
      'created_at': event.createdAt.millisecondsSinceEpoch,
    };
  }

  FinancialEventEvidenceLink _linkFromRow(Map<String, Object?> row) {
    return FinancialEventEvidenceLink(
      id: row['id']! as String,
      financialEventId: row['financial_event_id']! as String,
      smsItemId: row['sms_item_id']! as String,
      linkType: FinancialEventLinkTypeX.fromName(row['link_type'] as String?),
      confidence: (row['confidence']! as num).toDouble(),
      linkedAt: DateTime.fromMillisecondsSinceEpoch(row['linked_at']! as int),
    );
  }

  FinancialEvent _fromRow(Map<String, Object?> row) {
    final reasonsRaw = row['review_reasons'] as String?;
    return FinancialEvent(
      id: row['id']! as String,
      primarySmsItemId: row['primary_sms_item_id']! as String,
      eventType: FinancialEventTypeX.fromName(row['event_type'] as String?),
      role: FinancialEventRoleX.fromName(row['role'] as String?),
      status: FinancialEventStatusX.fromName(row['status'] as String?),
      direction:
          SmsTransactionDirectionX.fromName(row['direction'] as String?) ??
          SmsTransactionDirection.debit,
      amount: FieldConfidence<double>(
        value: (row['amount'] as num?)?.toDouble(),
        confidence: (row['amount_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(row['amount_source'] as String?),
        aiEvidence: row['amount_ai_evidence'] as String?,
        regexEvidence: row['amount_regex_evidence'] as String?,
      ),
      merchant: FieldConfidence<String>(
        value: row['merchant'] as String?,
        confidence: (row['merchant_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(row['merchant_source'] as String?),
        aiEvidence: row['merchant_ai_evidence'] as String?,
        regexEvidence: row['merchant_regex_evidence'] as String?,
      ),
      category: FieldConfidence<String>(
        value: row['category_id'] as String?,
        confidence: (row['category_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(row['category_source'] as String?),
      ),
      paymentMethod: FieldConfidence<PaymentMethod>(
        value: row['payment_method'] == null
            ? null
            : PaymentMethodX.fromName(row['payment_method'] as String?),
        confidence:
            (row['payment_method_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(
          row['payment_method_source'] as String?,
        ),
      ),
      accountMatch: FieldConfidence<String>(
        value: row['matched_account_id'] as String?,
        confidence: (row['account_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(row['account_source'] as String?),
      ),
      moneyMovement: FieldConfidence<bool>(
        value: switch (row['money_movement_value'] as int?) {
          1 => true,
          0 => false,
          _ => null,
        },
        confidence:
            (row['money_movement_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(
          row['money_movement_source'] as String?,
        ),
        regexEvidence: row['money_movement_regex_evidence'] as String?,
      ),
      transactionStatus: FieldConfidence<TransactionStatus>(
        value: row['transaction_status_value'] == null
            ? null
            : TransactionStatusX.fromName(
                row['transaction_status_value'] as String?,
              ),
        confidence:
            (row['transaction_status_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(
          row['transaction_status_source'] as String?,
        ),
      ),
      matchedCardId: row['matched_card_id'] as String?,
      normalizedSender: row['normalized_sender'] as String?,
      isOwnAccountTransfer: (row['is_own_account_transfer'] as int?) == 1,
      paymentProvider: FieldConfidence<PaymentProvider>(
        value: row['payment_provider_value'] == null
            ? null
            : PaymentProviderX.fromName(
                row['payment_provider_value'] as String?,
              ),
        confidence:
            (row['payment_provider_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(
          row['payment_provider_source'] as String?,
        ),
      ),
      merchantType: FieldConfidence<MerchantType>(
        value: row['merchant_type_value'] == null
            ? null
            : MerchantTypeX.fromName(row['merchant_type_value'] as String?),
        confidence:
            (row['merchant_type_confidence'] as num?)?.toDouble() ?? 0.0,
        source: EvidenceSourceX.fromName(
          row['merchant_type_source'] as String?,
        ),
        regexEvidence: row['merchant_type_evidence'] as String?,
      ),
      eventDate: DateTime.fromMillisecondsSinceEpoch(row['event_date']! as int),
      overallConfidence: (row['overall_confidence']! as num).toDouble(),
      confidenceLevel: ConfidenceLevel.values.byName(
        row['confidence_level']! as String,
      ),
      automationAction: AutomationActionX.fromName(
        row['automation_action'] as String?,
      ),
      needsReview: (row['needs_review']! as int) == 1,
      reviewReasons: reasonsRaw == null || reasonsRaw.isEmpty
          ? const []
          : reasonsRaw.split(_reasonSeparator),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      referenceNumber: row['reference_number'] as String?,
      linkedTransactionId: row['linked_transaction_id'] as String?,
      linkedEventId: row['linked_event_id'] as String?,
      subcategory: row['subcategory'] as String?,
      aiRawResponse: row['ai_raw_response'] as String?,
      aiModelVersion: row['ai_model_version'] as String?,
    );
  }
}
