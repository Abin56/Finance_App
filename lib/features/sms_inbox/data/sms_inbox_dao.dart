import 'package:sqflite/sqflite.dart';

import '../domain/parsed_sms_transaction.dart';
import '../domain/raw_sms_message.dart';
import '../domain/sms_duplicate_reason.dart';
import '../domain/sms_import_status.dart';
import '../domain/sms_inbox_item.dart';
import '../domain/sms_transaction_category.dart';
import '../domain/sms_transaction_direction.dart';
import 'sms_inbox_database.dart';

/// Thin sqflite CRUD over the `sms_inbox` table — no business logic here
/// (dedup handling, status transitions, scanning) lives in
/// [SmsInboxRepository]. Mirrors `FirestoreCrudRepository`'s
/// "persistence-only" role for the Firestore-backed features.
class SmsInboxDao {
  const SmsInboxDao(this._db);

  final SmsInboxDatabase _db;

  Database get _database => _db.database;

  /// Inserts a row, silently skipping it if [SmsInboxItem.messageKey] already
  /// exists (the `UNIQUE(message_key)` constraint) — this is what makes
  /// re-scanning the same inbox naturally idempotent: the same physical SMS
  /// re-read on every scan is recognized, not re-inserted. Returns true if a
  /// new row was actually inserted.
  ///
  /// Note this keys on the *message*, not the dedup key: a genuine duplicate
  /// (a different physical SMS describing the same payment) has its own
  /// message key and is therefore stored — flagged via
  /// [SmsInboxItem.duplicateOfId] rather than dropped. See
  /// [SmsInboxRepository.scanInbox].
  Future<bool> insertIfNew(SmsInboxItem item) async {
    final rowId = await _database.insert(
      SmsInboxDatabase.tableName,
      _toRow(item),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return rowId != 0;
  }

  /// The earliest-stored non-duplicate row sharing [dedupKey] — the
  /// "original" a new duplicate points at. Ordering by `created_at` keeps a
  /// duplicate chain flat: every duplicate references the one true original,
  /// never another duplicate, so deleting a duplicate can't orphan others.
  Future<SmsInboxItem?> findOriginalByDedupKey(String dedupKey) async {
    final rows = await _database.query(
      SmsInboxDatabase.tableName,
      where: 'dedup_key = ? AND duplicate_of_id IS NULL',
      whereArgs: [dedupKey],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Sets [status] on many rows in one batch — bulk Ignore over a large
  /// selection, without a round trip per id.
  Future<void> updateStatusMany(List<String> ids, {required SmsImportStatus status, DateTime? ignoredAt}) async {
    if (ids.isEmpty) return;

    final batch = _database.batch();
    for (final id in ids) {
      batch.update(
        SmsInboxDatabase.tableName,
        {'status': status.name, 'ignored_at': ?ignoredAt?.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateStatus(
    String id, {
    required SmsImportStatus status,
    String? linkedEntityId,
    String? linkedEntityRoute,
    DateTime? importedAt,
    DateTime? ignoredAt,
  }) async {
    await _database.update(
      SmsInboxDatabase.tableName,
      {
        'status': status.name,
        'linked_entity_id': ?linkedEntityId,
        'linked_entity_route': ?linkedEntityRoute,
        'imported_at': ?importedAt?.millisecondsSinceEpoch,
        'ignored_at': ?ignoredAt?.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SmsInboxItem>> getAll() async {
    final rows = await _database.query(SmsInboxDatabase.tableName, orderBy: 'received_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<List<SmsInboxItem>> getByStatus(SmsImportStatus status) async {
    final rows = await _database.query(
      SmsInboxDatabase.tableName,
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'received_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Clears the duplicate flag, returning the row to the normal inbox feed.
  /// Backs the user overruling a false positive — the detection rules are
  /// heuristics, and the user is the authority on their own messages.
  Future<void> clearDuplicateFlag(String id) async {
    await _database.update(
      SmsInboxDatabase.tableName,
      {'duplicate_of_id': null, 'duplicate_reason': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _database.delete(SmsInboxDatabase.tableName, where: 'id IN ($placeholders)', whereArgs: ids);
  }

  Map<String, Object?> _toRow(SmsInboxItem item) {
    final parsed = item.parsed;
    return {
      'id': item.id,
      'message_key': item.messageKey,
      'dedup_key': item.dedupKey,
      'duplicate_of_id': item.duplicateOfId,
      'duplicate_reason': item.duplicateReason?.name,
      'sender': item.rawMessage.address,
      'body': item.rawMessage.body,
      'received_at': item.rawMessage.date.millisecondsSinceEpoch,
      'direction': parsed?.direction.name,
      'amount': parsed?.amount,
      'merchant': parsed?.merchantOrSender,
      'bank_name': parsed?.bankName,
      'masked_account': parsed?.maskedAccountOrCard,
      'reference_number': parsed?.referenceNumber,
      'category': parsed?.category.name,
      'confidence': parsed?.confidence,
      'status': item.status.name,
      'linked_entity_id': item.linkedEntityId,
      'linked_entity_route': item.linkedEntityRoute,
      'imported_at': item.importedAt?.millisecondsSinceEpoch,
      'ignored_at': item.ignoredAt?.millisecondsSinceEpoch,
      'created_at': item.createdAt.millisecondsSinceEpoch,
    };
  }

  SmsInboxItem _fromRow(Map<String, Object?> row) {
    final amount = row['amount'] as double?;
    final directionName = row['direction'] as String?;
    final direction = SmsTransactionDirectionX.fromName(directionName);

    ParsedSmsTransaction? parsed;
    if (amount != null && direction != null) {
      parsed = ParsedSmsTransaction(
        amount: amount,
        direction: direction,
        dateTime: DateTime.fromMillisecondsSinceEpoch(row['received_at']! as int),
        category: SmsTransactionCategoryX.fromName(row['category'] as String?),
        confidence: (row['confidence'] as num?)?.toDouble() ?? 0.0,
        rawBody: row['body']! as String,
        merchantOrSender: row['merchant'] as String?,
        bankName: row['bank_name'] as String?,
        maskedAccountOrCard: row['masked_account'] as String?,
        referenceNumber: row['reference_number'] as String?,
      );
    }

    final duplicateOfId = row['duplicate_of_id'] as String?;

    return SmsInboxItem(
      id: row['id']! as String,
      messageKey: row['message_key']! as String,
      rawMessage: RawSmsMessage(
        address: row['sender']! as String,
        body: row['body']! as String,
        date: DateTime.fromMillisecondsSinceEpoch(row['received_at']! as int),
      ),
      parsed: parsed,
      dedupKey: row['dedup_key']! as String,
      duplicateOfId: duplicateOfId,
      duplicateReason: duplicateOfId == null
          ? null
          : SmsDuplicateReasonX.fromName(row['duplicate_reason'] as String?),
      status: SmsImportStatusX.fromName(row['status']! as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      linkedEntityId: row['linked_entity_id'] as String?,
      linkedEntityRoute: row['linked_entity_route'] as String?,
      importedAt: row['imported_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(row['imported_at']! as int),
      ignoredAt: row['ignored_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(row['ignored_at']! as int),
    );
  }
}
