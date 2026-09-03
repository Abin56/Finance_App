import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/financial_event/merchant_type.dart';
import '../domain/financial_event/payment_method.dart';
import '../domain/financial_event/payment_provider.dart';
import '../domain/learning/correction_event.dart';
import '../domain/learning/learned_field.dart';
import '../domain/learning/learning_source.dart';
import '../domain/learning/merchant_learning_profile.dart';
import 'sms_inbox_database.dart';

/// Thin sqflite CRUD over `merchant_learning_profiles`/
/// `merchant_learning_corrections` — persistence only, mirroring
/// [SmsInboxDatabase]'s other DAOs (e.g. `MerchantMemoryDao`). This DAO never
/// decides *what* to learn; it only stores exactly what a caller passes in.
/// Scanning/reading an SMS must never cause a profile to appear here —
/// [getOrCreateProfile] only creates one when a caller explicitly asks.
///
/// Privacy boundary: every column on both tables is one of a normalized
/// merchant key, an enum name, a counter, or a millisecond timestamp. There
/// is no column, insert path, or public method on this class capable of
/// accepting raw SMS body text, an OTP/CVV/PIN/password, a full account/card
/// number, a phone number, or a raw AI prompt/response — see
/// `merchant_learning_privacy_test.dart`.
class MerchantLearningDao {
  MerchantLearningDao(SmsInboxDatabase db, {Uuid? uuid})
    : this._(db.database, db.database, uuid: uuid);

  MerchantLearningDao._(this._database, this._root, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final DatabaseExecutor _database;

  /// Non-null only on the top-level (non-transactional) DAO — `.transaction`
  /// starts a fresh transaction from here. A DAO handed to a transaction
  /// callback (see [transaction]) has this set to `null`, so nesting a
  /// second transaction inside the first is a compile-time impossibility to
  /// call, not just a runtime foot-gun.
  final Database? _root;
  final Uuid _uuid;

  Future<MerchantLearningProfile?> getProfile(
    String userId,
    String merchantKey,
  ) async {
    final rows = await _database.query(
      SmsInboxDatabase.merchantLearningProfilesTableName,
      where: 'user_id = ? AND merchant_key = ?',
      whereArgs: [userId, merchantKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.single);
  }

  /// Creates an empty profile only when none exists yet — the caller (the
  /// repository, on an explicit user/AI classification) decides when that
  /// is warranted; this method never runs implicitly off an SMS scan.
  Future<MerchantLearningProfile> getOrCreateProfile(
    String userId,
    String merchantKey,
  ) async {
    final existing = await getProfile(userId, merchantKey);
    if (existing != null) return existing;

    final blank = MerchantLearningProfile(userId: userId, merchantKey: merchantKey);
    await _database.insert(
      SmsInboxDatabase.merchantLearningProfilesTableName,
      _toRow(blank),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return (await getProfile(userId, merchantKey)) ?? blank;
  }

  Future<List<MerchantLearningProfile>> listProfiles(String userId) async {
    final rows = await _database.query(
      SmsInboxDatabase.merchantLearningProfilesTableName,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.map(_fromRow).toList();
  }

  /// Persists [profile] as-is (upsert on the (user_id, merchant_key) primary
  /// key). Callers that also need to append a [CorrectionEvent] atomically
  /// alongside this write should use
  /// `MerchantLearningRepository.applyCorrection`, not this method directly.
  Future<void> saveProfile(MerchantLearningProfile profile) async {
    await _database.insert(
      SmsInboxDatabase.merchantLearningProfilesTableName,
      _toRow(profile),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProfile(String userId, String merchantKey) async {
    await _database.delete(
      SmsInboxDatabase.merchantLearningProfilesTableName,
      where: 'user_id = ? AND merchant_key = ?',
      whereArgs: [userId, merchantKey],
    );
  }

  /// Deletes every profile and correction this user has — a full "forget
  /// what you've learned about me" wipe.
  Future<void> clearAllForUser(String userId) async {
    await _database.delete(
      SmsInboxDatabase.merchantLearningProfilesTableName,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    await _database.delete(
      SmsInboxDatabase.merchantLearningCorrectionsTableName,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Appends one correction row. Append-only — never updates or deletes an
  /// existing row — so `getCorrectionHistory` always reconstructs full
  /// history, matching `MerchantCorrectionLog`'s in-memory invariant.
  Future<void> recordCorrection(String userId, CorrectionEvent event) async {
    await _database.insert(
      SmsInboxDatabase.merchantLearningCorrectionsTableName,
      _correctionToRow(userId, event, id: _uuid.v4()),
    );
  }

  Future<List<CorrectionEvent>> getCorrectionHistory(
    String userId,
    String merchantKey, {
    LearnedFieldType? field,
  }) async {
    final where = StringBuffer('user_id = ? AND merchant_key = ?');
    final whereArgs = <Object?>[userId, merchantKey];
    if (field != null) {
      where.write(' AND field = ?');
      whereArgs.add(field.name);
    }
    final rows = await _database.query(
      SmsInboxDatabase.merchantLearningCorrectionsTableName,
      where: where.toString(),
      whereArgs: whereArgs,
      orderBy: 'timestamp ASC',
    );
    return rows.map(_correctionFromRow).toList();
  }

  /// Runs [action] against a transactional [MerchantLearningDao] view — every
  /// write [action] performs through the DAO it receives either all commits
  /// or none do, so a profile update and its correction-history append never
  /// end up half-applied. See `MerchantLearningRepository.applyCorrection`.
  Future<T> transaction<T>(
    Future<T> Function(MerchantLearningDao txnDao) action,
  ) {
    final root = _root;
    if (root == null) {
      throw StateError('Cannot start a nested transaction on a transactional DAO.');
    }
    return root.transaction((txn) {
      return action(MerchantLearningDao._(txn, null, uuid: _uuid));
    });
  }

  Map<String, Object?> _toRow(MerchantLearningProfile profile) {
    final row = <String, Object?>{
      'user_id': profile.userId,
      'merchant_key': profile.merchantKey,
    };
    _writeField(row, 'merchant_type', profile.merchantType, (v) => v.name);
    _writeField(row, 'category', profile.category, (v) => v);
    _writeField(row, 'subcategory', profile.subcategory, (v) => v);
    _writeField(row, 'payment_provider', profile.paymentProvider, (v) => v.name);
    _writeField(row, 'payment_method', profile.paymentMethod, (v) => v.name);
    return row;
  }

  void _writeField<T>(
    Map<String, Object?> row,
    String prefix,
    LearnedField<T> field,
    String Function(T value) encode,
  ) {
    row['${prefix}_value'] = field.hasValue ? encode(field.value as T) : null;
    row['${prefix}_source'] = field.source.name;
    row['${prefix}_confirmations'] = field.confirmations;
    row['${prefix}_corrections'] = field.corrections;
    row['${prefix}_last_updated_at'] = field.lastUpdatedAt?.millisecondsSinceEpoch;
  }

  MerchantLearningProfile _fromRow(Map<String, Object?> row) {
    return MerchantLearningProfile(
      userId: row['user_id']! as String,
      merchantKey: row['merchant_key']! as String,
      merchantType: _readField(row, 'merchant_type', MerchantTypeX.fromName),
      category: _readField(row, 'category', (v) => v),
      subcategory: _readField(row, 'subcategory', (v) => v),
      paymentProvider: _readField(row, 'payment_provider', PaymentProviderX.fromName),
      paymentMethod: _readField(row, 'payment_method', PaymentMethodX.fromName),
    );
  }

  LearnedField<T> _readField<T>(
    Map<String, Object?> row,
    String prefix,
    T Function(String raw) decode,
  ) {
    final rawValue = row['${prefix}_value'] as String?;
    final lastUpdatedAtMillis = row['${prefix}_last_updated_at'] as int?;
    return LearnedField<T>(
      value: rawValue == null ? null : decode(rawValue),
      source: LearningSourceX.fromName(row['${prefix}_source'] as String?),
      confirmations: (row['${prefix}_confirmations'] as int?) ?? 0,
      corrections: (row['${prefix}_corrections'] as int?) ?? 0,
      lastUpdatedAt: lastUpdatedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastUpdatedAtMillis),
    );
  }

  Map<String, Object?> _correctionToRow(
    String userId,
    CorrectionEvent event, {
    required String id,
  }) {
    return {
      'id': id,
      'user_id': userId,
      'merchant_key': event.merchantKey,
      'field': event.field.name,
      'old_value': event.oldValue,
      'new_value': event.newValue,
      'source': event.source.name,
      'timestamp': event.timestamp.millisecondsSinceEpoch,
    };
  }

  CorrectionEvent _correctionFromRow(Map<String, Object?> row) {
    return CorrectionEvent(
      merchantKey: row['merchant_key']! as String,
      field: _fieldFromName(row['field']! as String),
      oldValue: row['old_value'] as String?,
      newValue: row['new_value'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp']! as int),
      source: LearningSourceX.fromName(row['source'] as String?),
    );
  }

  LearnedFieldType _fieldFromName(String name) => LearnedFieldType.values.firstWhere(
    (f) => f.name == name,
    orElse: () => LearnedFieldType.category,
  );
}
