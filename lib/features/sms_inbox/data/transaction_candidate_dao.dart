import 'package:sqflite/sqflite.dart';

import '../domain/sms_confidence_scorer.dart';
import '../domain/sms_transaction_category.dart';
import '../domain/sms_transaction_direction.dart';
import '../domain/transaction_candidate.dart';
import 'sms_inbox_database.dart';

/// Thin sqflite CRUD over `sms_transaction_candidates` — mirrors
/// [SmsInboxDao]'s "persistence-only" role; matching/scoring logic lives in
/// `TransactionCandidateBuilder`.
class TransactionCandidateDao {
  const TransactionCandidateDao(this._db);

  final SmsInboxDatabase _db;

  Database get _database => _db.database;

  /// Reasons are free-text sentences (see [TransactionCandidate.reviewReasons])
  /// that never contain this control character, so joining/splitting on it
  /// is safe without needing full JSON encoding for what is otherwise a
  /// flat list of strings.
  static const String _reasonSeparator = '';

  /// Upserts one candidate. `sms_item_id` is uniquely indexed, so re-running
  /// candidate generation for an already-scored message (e.g. after the
  /// user's accounts changed) replaces its previous verdict rather than
  /// accumulating stale duplicates.
  Future<void> upsert(TransactionCandidate candidate) async {
    await _database.insert(
      SmsInboxDatabase.transactionCandidatesTableName,
      _toRow(candidate),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The [TransactionCandidate.smsItemId]s that already have a candidate
  /// row — generation skips these rather than re-scoring every pending
  /// message on every scan.
  Future<Set<String>> existingSmsItemIds() async {
    final rows = await _database.query(SmsInboxDatabase.transactionCandidatesTableName, columns: ['sms_item_id']);
    return rows.map((row) => row['sms_item_id']! as String).toSet();
  }

  Future<List<TransactionCandidate>> getAll() async {
    final rows = await _database.query(SmsInboxDatabase.transactionCandidatesTableName, orderBy: 'created_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<TransactionCandidate?> getBySmsItemId(String smsItemId) async {
    final rows = await _database.query(
      SmsInboxDatabase.transactionCandidatesTableName,
      where: 'sms_item_id = ?',
      whereArgs: [smsItemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Removes candidates whose source SMS was deleted — called alongside
  /// [SmsInboxDao.deleteByIds] so a candidate row never outlives the message
  /// it was built from.
  Future<void> deleteBySmsItemIds(List<String> smsItemIds) async {
    if (smsItemIds.isEmpty) return;
    final placeholders = List.filled(smsItemIds.length, '?').join(',');
    await _database.delete(
      SmsInboxDatabase.transactionCandidatesTableName,
      where: 'sms_item_id IN ($placeholders)',
      whereArgs: smsItemIds,
    );
  }

  Map<String, Object?> _toRow(TransactionCandidate candidate) {
    return {
      'id': candidate.id,
      'sms_item_id': candidate.smsItemId,
      'amount': candidate.amount,
      'direction': candidate.direction.name,
      'event_type': candidate.eventType.name,
      'transaction_date': candidate.transactionDate.millisecondsSinceEpoch,
      'merchant': candidate.merchant,
      'bank_name': candidate.bankName,
      'matched_account_id': candidate.matchedAccountId,
      'matched_card_id': candidate.matchedCardId,
      'reference_number': candidate.referenceNumber,
      'confidence_level': candidate.confidenceLevel.name,
      'confidence_score': candidate.confidenceScore,
      'needs_review': candidate.needsReview ? 1 : 0,
      'review_reasons': candidate.reviewReasons.isEmpty ? null : candidate.reviewReasons.join(_reasonSeparator),
      'created_at': candidate.createdAt.millisecondsSinceEpoch,
    };
  }

  TransactionCandidate _fromRow(Map<String, Object?> row) {
    final reasonsRaw = row['review_reasons'] as String?;
    return TransactionCandidate(
      id: row['id']! as String,
      smsItemId: row['sms_item_id']! as String,
      amount: (row['amount']! as num).toDouble(),
      direction: SmsTransactionDirectionX.fromName(row['direction'] as String?)!,
      eventType: SmsTransactionCategoryX.fromName(row['event_type'] as String?),
      transactionDate: DateTime.fromMillisecondsSinceEpoch(row['transaction_date']! as int),
      merchant: row['merchant'] as String?,
      bankName: row['bank_name'] as String?,
      matchedAccountId: row['matched_account_id'] as String?,
      matchedCardId: row['matched_card_id'] as String?,
      referenceNumber: row['reference_number'] as String?,
      confidenceLevel: ConfidenceLevel.values.byName(row['confidence_level']! as String),
      confidenceScore: (row['confidence_score']! as num).toDouble(),
      needsReview: (row['needs_review']! as int) == 1,
      reviewReasons: reasonsRaw == null || reasonsRaw.isEmpty ? const [] : reasonsRaw.split(_reasonSeparator),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }
}
