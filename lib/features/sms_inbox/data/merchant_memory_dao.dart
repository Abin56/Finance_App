import 'package:sqflite/sqflite.dart';

import '../../transactions/domain/transaction_type.dart';
import '../domain/merchant/merchant_memory.dart';
import 'sms_inbox_database.dart';

/// Thin sqflite CRUD over the `sms_merchant_memory` table. Persistence only —
/// which memory actually wins for a given merchant is a domain decision and
/// lives in `MerchantCategorySuggester`, mirroring how [SmsInboxDao] keeps
/// dedup/status rules out of the data layer.
class MerchantMemoryDao {
  const MerchantMemoryDao(this._db);

  final SmsInboxDatabase _db;

  Database get _database => _db.database;

  Future<List<MerchantMemory>> getAll() async {
    final rows = await _database.query(SmsInboxDatabase.merchantMemoryTableName);
    return rows.map(_fromRow).toList();
  }

  /// Records one confirmed user choice. Uses SQLite's `ON CONFLICT ... DO
  /// UPDATE` against the composite primary key so a repeat choice atomically
  /// bumps `times_used` instead of needing a read-then-write that could race
  /// two conversions saving at once.
  Future<void> record({
    required String merchantKey,
    required TransactionType transactionType,
    required String categoryId,
    required DateTime at,
  }) async {
    await _database.rawInsert(
      '''
      INSERT INTO ${SmsInboxDatabase.merchantMemoryTableName}
        (merchant_key, transaction_type, category_id, times_used, last_used_at)
      VALUES (?, ?, ?, 1, ?)
      ON CONFLICT(merchant_key, transaction_type, category_id) DO UPDATE SET
        times_used = times_used + 1,
        last_used_at = excluded.last_used_at
      ''',
      [merchantKey, transactionType.name, categoryId, at.millisecondsSinceEpoch],
    );
  }

  MerchantMemory _fromRow(Map<String, Object?> row) {
    return MerchantMemory(
      merchantKey: row['merchant_key']! as String,
      transactionType: TransactionTypeX.fromName(row['transaction_type']! as String),
      categoryId: row['category_id']! as String,
      timesUsed: row['times_used']! as int,
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(row['last_used_at']! as int),
    );
  }
}
