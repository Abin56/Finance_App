import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/sms_message_key.dart';

/// Owns the single sqflite [Database] backing the SMS Inbox. This is the
/// app's only local relational store — deliberately separate from Firestore
/// (see `SmsInboxRepository`'s doc comment) so pending/ignored SMS metadata
/// never leaves the device before the user converts it. The merchant-memory
/// table lives here for the same reason: it is derived from that same local
/// SMS data and must not sync.
class SmsInboxDatabase {
  SmsInboxDatabase._(this.database);

  final Database database;

  static const String tableName = 'sms_inbox';
  static const String merchantMemoryTableName = 'sms_merchant_memory';
  static const String deletedMessageKeysTableName = 'sms_deleted_message_keys';

  /// v3 — added `sms_deleted_message_keys`, a tombstone table recording the
  /// `message_key` of every row the user has ever deleted. Without it,
  /// deleting a row only removed it from `sms_inbox`; the next `scanInbox()`
  /// re-read the same physical device message, found no row with that
  /// `message_key`, and re-inserted it as "new" — silently undoing the
  /// user's delete (and, for an already-converted SMS, resurrecting a
  /// pending row for a message that already has a real transaction behind
  /// it). `scanInbox()` now checks this table before inserting.
  static const int schemaVersion = 3;

  static SmsInboxDatabase? _instance;

  /// Opens (or creates) the database once at app startup — call from
  /// `main.dart` alongside `LocalSettingsService.init()`. Safe to call more
  /// than once; subsequent calls are no-ops.
  static Future<SmsInboxDatabase> init() async {
    final existing = _instance;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'sms_inbox.db');

    final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) => _onCreate(db),
      onUpgrade: _onUpgrade,
    );

    final instance = SmsInboxDatabase._(db);
    _instance = instance;
    return instance;
  }

  static Future<void> _onCreate(Database db) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id TEXT PRIMARY KEY,
        message_key TEXT NOT NULL UNIQUE,
        dedup_key TEXT NOT NULL,
        duplicate_of_id TEXT,
        duplicate_reason TEXT,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        direction TEXT,
        amount REAL,
        merchant TEXT,
        bank_name TEXT,
        masked_account TEXT,
        reference_number TEXT,
        category TEXT,
        confidence REAL,
        status TEXT NOT NULL DEFAULT 'pending',
        linked_entity_id TEXT,
        linked_entity_route TEXT,
        imported_at INTEGER,
        ignored_at INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    await _createInboxIndexes(db);
    await _createMerchantMemoryTable(db);
    await _createDeletedMessageKeysTable(db);
  }

  /// One row per deleted [SmsInboxItem.messageKey] — a tombstone so a
  /// re-scan of the device inbox never resurrects a message the user
  /// explicitly deleted. `deleted_at` exists for potential future pruning
  /// (e.g. a "keep tombstones for 1 year" policy) but nothing reads it today.
  static Future<void> _createDeletedMessageKeysTable(Database db) async {
    await db.execute('''
      CREATE TABLE $deletedMessageKeysTableName (
        message_key TEXT PRIMARY KEY,
        deleted_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createInboxIndexes(Database db) async {
    await db.execute('CREATE INDEX idx_sms_inbox_status ON $tableName(status)');
    await db.execute('CREATE INDEX idx_sms_inbox_received_at ON $tableName(received_at)');
    // No longer UNIQUE, but still the lookup that finds an incoming message's
    // original when deciding whether it is a duplicate.
    await db.execute('CREATE INDEX idx_sms_inbox_dedup_key ON $tableName(dedup_key)');
    await db.execute('CREATE INDEX idx_sms_inbox_duplicate_of ON $tableName(duplicate_of_id)');
  }

  /// One row per (merchant, transaction type, category) the user has actually
  /// chosen, with a count — see `MerchantMemory`. The composite primary key
  /// is what lets a repeat choice be a single upsert that bumps `times_used`.
  static Future<void> _createMerchantMemoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE $merchantMemoryTableName (
        merchant_key TEXT NOT NULL,
        transaction_type TEXT NOT NULL,
        category_id TEXT NOT NULL,
        times_used INTEGER NOT NULL DEFAULT 1,
        last_used_at INTEGER NOT NULL,
        PRIMARY KEY (merchant_key, transaction_type, category_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sms_merchant_memory_lookup ON $merchantMemoryTableName(merchant_key, transaction_type)',
    );
  }

  /// SQLite cannot drop a column constraint in place, so removing
  /// `UNIQUE(dedup_key)` means rebuilding the table. Every existing row is
  /// preserved verbatim — including its id, so any `linked_entity_id` an
  /// already-converted SMS carries stays intact and no financial record is
  /// touched.
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableName RENAME TO ${tableName}_v1');
      // Renaming a table in SQLite carries its indexes along *under their
      // original names*, so re-creating the schema below would collide with
      // them. They belong to the table being dropped anyway.
      await db.execute('DROP INDEX IF EXISTS idx_sms_inbox_status');
      await db.execute('DROP INDEX IF EXISTS idx_sms_inbox_received_at');

      await _onCreate(db);

      // message_key is seeded to the row's own id purely to satisfy the NOT
      // NULL/UNIQUE column during the copy; the real key is computed from the
      // message below. Using the id guarantees uniqueness in the interim.
      await db.execute('''
        INSERT INTO $tableName (
          id, message_key, dedup_key, sender, body, received_at, direction, amount,
          merchant, bank_name, masked_account, reference_number, category, confidence,
          status, linked_entity_id, linked_entity_route, imported_at, ignored_at, created_at
        )
        SELECT
          id, id, dedup_key, sender, body, received_at, direction, amount,
          merchant, bank_name, masked_account, reference_number, category, confidence,
          status, linked_entity_id, linked_entity_route, imported_at, ignored_at, created_at
        FROM ${tableName}_v1
      ''');

      await _backfillMessageKeys(db);
      await db.execute('DROP TABLE ${tableName}_v1');
    }
    // The v1→v2 branch above already creates this table via its own
    // _onCreate call, so guard against a double-create when a v1 database
    // jumps straight to v3.
    if (oldVersion == 2) {
      await _createDeletedMessageKeysTable(db);
    }
  }

  /// Computes the real [SmsMessageKey] for every migrated row. This must
  /// happen, not just be left at the id placeholder: the next scan re-reads
  /// these same physical messages and computes their true message key, so a
  /// row still holding a placeholder would fail to match and be re-inserted
  /// as a bogus duplicate of itself.
  static Future<void> _backfillMessageKeys(Database db) async {
    final rows = await db.query(tableName, columns: ['id', 'sender', 'body', 'received_at']);

    final batch = db.batch();
    for (final row in rows) {
      final messageKey = SmsMessageKey.compute(
        sender: row['sender']! as String,
        dateTime: DateTime.fromMillisecondsSinceEpoch(row['received_at']! as int),
        body: row['body']! as String,
      );
      batch.update(tableName, {'message_key': messageKey}, where: 'id = ?', whereArgs: [row['id']]);
    }
    await batch.commit(noResult: true);
  }

  /// Test-only seam: opens an in-memory database against whatever
  /// `databaseFactory` the test has configured (e.g. `sqflite_common_ffi`),
  /// sharing the same schema as [init]'s real on-disk path, without
  /// touching platform channels.
  @visibleForTesting
  static Future<SmsInboxDatabase> openInMemoryForTest() async {
    // singleInstance: false — otherwise sqflite caches/reuses the same
    // connection for the ":memory:" path across tests, leaking rows from
    // one test's database into the next.
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _onCreate(db),
        onUpgrade: _onUpgrade,
        singleInstance: false,
      ),
    );
    final instance = SmsInboxDatabase._(db);
    _instance = instance;
    return instance;
  }

  /// Test-only seam for the v1→v2 migration: creates the *old* schema so a
  /// test can seed it and then reopen at [schemaVersion] to exercise
  /// [_onUpgrade] against real rows.
  @visibleForTesting
  static Future<Database> openV1ForTest(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $tableName (
              id TEXT PRIMARY KEY,
              dedup_key TEXT NOT NULL UNIQUE,
              sender TEXT NOT NULL,
              body TEXT NOT NULL,
              received_at INTEGER NOT NULL,
              direction TEXT,
              amount REAL,
              merchant TEXT,
              bank_name TEXT,
              masked_account TEXT,
              reference_number TEXT,
              category TEXT,
              confidence REAL,
              status TEXT NOT NULL DEFAULT 'pending',
              linked_entity_id TEXT,
              linked_entity_route TEXT,
              imported_at INTEGER,
              ignored_at INTEGER,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX idx_sms_inbox_status ON $tableName(status)');
          await db.execute('CREATE INDEX idx_sms_inbox_received_at ON $tableName(received_at)');
        },
      ),
    );
  }

  /// Test-only seam: reopens [path] at [schemaVersion], running [_onUpgrade].
  @visibleForTesting
  static Future<SmsInboxDatabase> openUpgradedForTest(String path) async {
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _onCreate(db),
        onUpgrade: _onUpgrade,
        singleInstance: false,
      ),
    );
    final instance = SmsInboxDatabase._(db);
    _instance = instance;
    return instance;
  }

  @visibleForTesting
  static void debugReset() => _instance = null;

  /// The already-[init]'d singleton — `main.dart` awaits [init] before
  /// `runApp`, so every Riverpod provider built afterwards can read this
  /// synchronously, same as `LocalSettingsService`'s init-once pattern.
  static SmsInboxDatabase get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('SmsInboxDatabase.init() must be called before use.');
    }
    return instance;
  }
}
