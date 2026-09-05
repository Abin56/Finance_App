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
  static const String transactionCandidatesTableName =
      'sms_transaction_candidates';
  static const String financialEventsTableName = 'financial_events';
  static const String smsFinancialEventLinksTableName =
      'sms_financial_event_links';
  static const String merchantLearningProfilesTableName =
      'merchant_learning_profiles';
  static const String merchantLearningCorrectionsTableName =
      'merchant_learning_corrections';

  /// v3 — added `sms_deleted_message_keys`, a tombstone table recording the
  /// `message_key` of every row the user has ever deleted. Without it,
  /// deleting a row only removed it from `sms_inbox`; the next `scanInbox()`
  /// re-read the same physical device message, found no row with that
  /// `message_key`, and re-inserted it as "new" — silently undoing the
  /// user's delete (and, for an already-converted SMS, resurrecting a
  /// pending row for a message that already has a real transaction behind
  /// it). `scanInbox()` now checks this table before inserting.
  ///
  /// v4 — added `sms_transaction_candidates`, purely additive: one row per
  /// [tableName] row that `TransactionCandidateBuilder` was able to produce
  /// a candidate for (account/card match + confidence). No existing table,
  /// column, or row is touched by this upgrade.
  ///
  /// v5 — added `financial_events` and `sms_financial_event_links`, purely
  /// additive, for the AI-hybrid `FinancialEvent` engine. This replaces the
  /// old flat `duplicate_of_id` chain as the anchor for "multiple SMS
  /// describing one real-world transaction": the event row is the anchor,
  /// and every contributing SMS gets its own link row, so deleting any one
  /// SMS (including what would have been the old chain's "original") only
  /// removes its own link — it can no longer orphan the others or split one
  /// duplicate chain into two (see `SmsInboxDao.findOriginalByDedupKey`'s
  /// known-limitation comment, which this table pair structurally fixes for
  /// events processed by the new pipeline; the legacy `duplicate_of_id`
  /// columns are untouched and keep working for the physical-SMS duplicate
  /// review flow).
  ///
  /// v6 — added `money_movement_*`/`transaction_status_*`/
  /// `is_own_account_transfer` columns to `financial_events`, purely
  /// additive (`ALTER TABLE ... ADD COLUMN`, nullable/defaulted so every
  /// existing row stays valid). Backs the Phase 2 distinction between a
  /// reminder/failed/pending message and money that actually moved — see
  /// `FinancialEvent.moneyMovement`'s doc comment.
  ///
  /// v7 — added `payment_provider_*`/`merchant_type_*` columns to
  /// `financial_events`, purely additive. Backs the Phase 3 distinction
  /// between the merchant (who was paid) and the payment provider/app that
  /// moved the money (PhonePe, Google Pay, ...) — see
  /// `FinancialEvent.paymentProvider`'s doc comment.
  ///
  /// v8 — added `merchant_learning_profiles`/`merchant_learning_corrections`,
  /// purely additive. Persists the in-memory `MerchantLearningStore`/
  /// `MerchantCorrectionLog` (see `lib/features/sms_inbox/domain/learning/`)
  /// so learned merchant fields survive an app restart. Only normalized
  /// merchant identity + learning metadata is stored here — never raw SMS
  /// body, OTP, account/card numbers, phone numbers, or AI prompts/responses;
  /// see `MerchantLearningDao`'s doc comment for the full boundary.
  ///
  /// v9 — added `source` to [tableName] (`'deviceSms'`/`'notification'`,
  /// defaulted so every existing row is correctly backfilled as
  /// `'deviceSms'` — every row before this version came from the device SMS
  /// provider). Backs the notification-listener capture path (see
  /// `NotificationCaptureListenerService`) that lets RCS-only bank alerts —
  /// which never reach `content://sms` — be scanned alongside real SMS.
  static const int schemaVersion = 9;

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
        source TEXT NOT NULL DEFAULT 'deviceSms',
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
    await _createTransactionCandidatesTable(db);
    await _createFinancialEventsTable(db);
    await _createSmsFinancialEventLinksTable(db);
    await _createMerchantLearningTables(db);
  }

  /// `merchant_learning_profiles` — one row per (user, merchant), one column
  /// pair (`value`/`source`/`confirmations`/`corrections`/`last_updated_at`)
  /// per `LearnedFieldType` — mirrors `MerchantLearningProfile` field for
  /// field. `merchant_learning_corrections` is the append-only history
  /// backing `MerchantCorrectionLog`. Neither table has a column capable of
  /// holding raw SMS text, OTP/CVV/PIN/password, a full account/card number,
  /// a phone number, or an AI prompt/response — only normalized merchant
  /// keys, enum names, counters, and timestamps, matching
  /// `MerchantLearningProfile`/`LearnedField`/`CorrectionEvent`'s own
  /// privacy-safe shape exactly.
  static Future<void> _createMerchantLearningTables(Database db) async {
    await db.execute('''
      CREATE TABLE $merchantLearningProfilesTableName (
        user_id TEXT NOT NULL,
        merchant_key TEXT NOT NULL,
        merchant_type_value TEXT,
        merchant_type_source TEXT,
        merchant_type_confirmations INTEGER NOT NULL DEFAULT 0,
        merchant_type_corrections INTEGER NOT NULL DEFAULT 0,
        merchant_type_last_updated_at INTEGER,
        category_value TEXT,
        category_source TEXT,
        category_confirmations INTEGER NOT NULL DEFAULT 0,
        category_corrections INTEGER NOT NULL DEFAULT 0,
        category_last_updated_at INTEGER,
        subcategory_value TEXT,
        subcategory_source TEXT,
        subcategory_confirmations INTEGER NOT NULL DEFAULT 0,
        subcategory_corrections INTEGER NOT NULL DEFAULT 0,
        subcategory_last_updated_at INTEGER,
        payment_provider_value TEXT,
        payment_provider_source TEXT,
        payment_provider_confirmations INTEGER NOT NULL DEFAULT 0,
        payment_provider_corrections INTEGER NOT NULL DEFAULT 0,
        payment_provider_last_updated_at INTEGER,
        payment_method_value TEXT,
        payment_method_source TEXT,
        payment_method_confirmations INTEGER NOT NULL DEFAULT 0,
        payment_method_corrections INTEGER NOT NULL DEFAULT 0,
        payment_method_last_updated_at INTEGER,
        PRIMARY KEY (user_id, merchant_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE $merchantLearningCorrectionsTableName (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        merchant_key TEXT NOT NULL,
        field TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        source TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_merchant_learning_corrections_lookup '
      'ON $merchantLearningCorrectionsTableName(user_id, merchant_key, field)',
    );
  }

  /// One row per real-world transaction the AI-hybrid engine has identified
  /// — see `FinancialEvent`. Unlike [transactionCandidatesTableName], this
  /// is not 1:1 with a single SMS: any number of [smsFinancialEventLinksTableName]
  /// rows can point at one event.
  static Future<void> _createFinancialEventsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $financialEventsTableName (
        id TEXT PRIMARY KEY,
        primary_sms_item_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT NOT NULL,
        direction TEXT NOT NULL,
        normalized_sender TEXT,
        amount REAL,
        amount_confidence REAL,
        amount_source TEXT,
        amount_ai_evidence TEXT,
        amount_regex_evidence TEXT,
        merchant TEXT,
        merchant_confidence REAL,
        merchant_source TEXT,
        merchant_ai_evidence TEXT,
        merchant_regex_evidence TEXT,
        category_id TEXT,
        category_confidence REAL,
        category_source TEXT,
        subcategory TEXT,
        payment_method TEXT,
        payment_method_confidence REAL,
        payment_method_source TEXT,
        matched_account_id TEXT,
        matched_card_id TEXT,
        account_confidence REAL,
        account_source TEXT,
        money_movement_value INTEGER,
        money_movement_confidence REAL,
        money_movement_source TEXT,
        money_movement_regex_evidence TEXT,
        transaction_status_value TEXT,
        transaction_status_confidence REAL,
        transaction_status_source TEXT,
        is_own_account_transfer INTEGER NOT NULL DEFAULT 0,
        payment_provider_value TEXT,
        payment_provider_confidence REAL,
        payment_provider_source TEXT,
        merchant_type_value TEXT,
        merchant_type_confidence REAL,
        merchant_type_source TEXT,
        merchant_type_evidence TEXT,
        event_date INTEGER NOT NULL,
        overall_confidence REAL NOT NULL,
        confidence_level TEXT NOT NULL,
        automation_action TEXT NOT NULL,
        needs_review INTEGER NOT NULL,
        review_reasons TEXT,
        reference_number TEXT,
        linked_transaction_id TEXT,
        linked_event_id TEXT,
        ai_raw_response TEXT,
        ai_model_version TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_financial_events_status ON $financialEventsTableName(status)',
    );
    await db.execute(
      'CREATE INDEX idx_financial_events_reference ON $financialEventsTableName(reference_number)',
    );
    await db.execute(
      'CREATE INDEX idx_financial_events_linked_event ON $financialEventsTableName(linked_event_id)',
    );
    // Backs TransactionMatcher's weak-signal "same sender + amount, no
    // reference number to confirm" possible-duplicate check.
    await db.execute(
      'CREATE INDEX idx_financial_events_sender_amount ON $financialEventsTableName(normalized_sender, amount)',
    );
  }

  /// One row per SMS contributing to a [financialEventsTableName] row — see
  /// `FinancialEventEvidenceLink`. `sms_item_id` is `UNIQUE`: one SMS
  /// describes exactly one event in practice, which keeps "does this SMS
  /// already have an event?" an O(1) lookup. No FK/cascade at the SQL level
  /// (same rationale as [transactionCandidatesTableName]'s doc comment —
  /// sqflite's cascade support is inconsistent across platforms); deleting a
  /// linked SMS or event is the DAO's explicit responsibility.
  static Future<void> _createSmsFinancialEventLinksTable(Database db) async {
    await db.execute('''
      CREATE TABLE $smsFinancialEventLinksTableName (
        id TEXT PRIMARY KEY,
        financial_event_id TEXT NOT NULL,
        sms_item_id TEXT NOT NULL,
        link_type TEXT NOT NULL,
        confidence REAL NOT NULL,
        linked_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_sms_fe_links_sms_item ON $smsFinancialEventLinksTableName(sms_item_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sms_fe_links_event ON $smsFinancialEventLinksTableName(financial_event_id)',
    );
  }

  /// One row per [tableName] row a `TransactionCandidateBuilder` run
  /// produced a candidate for — see `TransactionCandidate`. `sms_item_id`
  /// is not declared `UNIQUE`/a foreign key at the SQL level (sqflite's
  /// ON DELETE CASCADE support is inconsistent across platforms), so
  /// candidate regeneration/cleanup is the DAO's responsibility, same
  /// posture as `duplicate_of_id` on [tableName] itself.
  static Future<void> _createTransactionCandidatesTable(Database db) async {
    await db.execute('''
      CREATE TABLE $transactionCandidatesTableName (
        id TEXT PRIMARY KEY,
        sms_item_id TEXT NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        event_type TEXT NOT NULL,
        transaction_date INTEGER NOT NULL,
        merchant TEXT,
        bank_name TEXT,
        matched_account_id TEXT,
        matched_card_id TEXT,
        reference_number TEXT,
        confidence_level TEXT NOT NULL,
        confidence_score REAL NOT NULL,
        needs_review INTEGER NOT NULL,
        review_reasons TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_sms_transaction_candidates_sms_item_id ON $transactionCandidatesTableName(sms_item_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sms_transaction_candidates_needs_review ON $transactionCandidatesTableName(needs_review)',
    );
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
    await db.execute(
      'CREATE INDEX idx_sms_inbox_received_at ON $tableName(received_at)',
    );
    // No longer UNIQUE, but still the lookup that finds an incoming message's
    // original when deciding whether it is a duplicate.
    await db.execute(
      'CREATE INDEX idx_sms_inbox_dedup_key ON $tableName(dedup_key)',
    );
    await db.execute(
      'CREATE INDEX idx_sms_inbox_duplicate_of ON $tableName(duplicate_of_id)',
    );
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
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
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
    // jumps straight to v3 (or further).
    if (oldVersion == 2) {
      await _createDeletedMessageKeysTable(db);
    }
    // Same guard for v4's table: a v1 database jumping straight to v4 already
    // got it from the _onCreate call above; only v2/v3 databases need it
    // created here.
    if (oldVersion == 2 || oldVersion == 3) {
      await _createTransactionCandidatesTable(db);
    }
    // v5's two new tables are purely additive, but — same guard rationale as
    // the v2/v3-v4 blocks above — a v1 database already got them from the
    // v1→v2 branch's full `_onCreate` rebuild (which includes every current
    // table, financial_events included); only a v2/v3/v4 database, which
    // never went through that rebuild, needs them created here. `oldVersion
    // < 5` alone double-creates the table for a v1→v6 jump and crashes.
    if (oldVersion >= 2 && oldVersion < 5) {
      await _createFinancialEventsTable(db);
      await _createSmsFinancialEventLinksTable(db);
    }
    // v6's columns are included directly in _createFinancialEventsTable
    // above, so any database jumping from below v5 straight to v6 already
    // has them from that fresh create — only a database already sitting at
    // exactly v5 needs the ALTER TABLE additions here.
    if (oldVersion == 5) {
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN money_movement_value INTEGER',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN money_movement_confidence REAL',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN money_movement_source TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN money_movement_regex_evidence TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN transaction_status_value TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN transaction_status_confidence REAL',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN transaction_status_source TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN is_own_account_transfer INTEGER NOT NULL DEFAULT 0',
      );
    }
    // v7's columns are included directly in _createFinancialEventsTable
    // above, so a database jumping from below v5 straight to v7 already has
    // them from that fresh create — only a database sitting at exactly v5
    // or v6 needs the ALTER TABLE additions here.
    if (oldVersion == 5 || oldVersion == 6) {
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN payment_provider_value TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN payment_provider_confidence REAL',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN payment_provider_source TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN merchant_type_value TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN merchant_type_confidence REAL',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN merchant_type_source TEXT',
      );
      await db.execute(
        'ALTER TABLE $financialEventsTableName ADD COLUMN merchant_type_evidence TEXT',
      );
    }
    // v8's two new tables are purely additive, but — same guard rationale as
    // every prior additive step above — a v1 database already got them from
    // the v1→v2 branch's full `_onCreate` rebuild; only a v2..v7 database,
    // which never went through that rebuild, needs them created here.
    if (oldVersion >= 2 && oldVersion < 8) {
      await _createMerchantLearningTables(db);
    }
    // v9's column is included directly in the CREATE TABLE above, so a
    // database jumping from v1 straight to v9 already has it from the
    // v1→v2 branch's full rebuild; every other pre-v9 database needs the
    // ALTER TABLE here. DEFAULT 'deviceSms' backfills every existing row
    // correctly — nothing before this version could have come from anywhere
    // but the device SMS provider.
    if (oldVersion >= 2 && oldVersion < 9) {
      await db.execute(
        "ALTER TABLE $tableName ADD COLUMN source TEXT NOT NULL DEFAULT 'deviceSms'",
      );
    }
  }

  /// Computes the real [SmsMessageKey] for every migrated row. This must
  /// happen, not just be left at the id placeholder: the next scan re-reads
  /// these same physical messages and computes their true message key, so a
  /// row still holding a placeholder would fail to match and be re-inserted
  /// as a bogus duplicate of itself.
  static Future<void> _backfillMessageKeys(Database db) async {
    final rows = await db.query(
      tableName,
      columns: ['id', 'sender', 'body', 'received_at'],
    );

    final batch = db.batch();
    for (final row in rows) {
      final messageKey = SmsMessageKey.compute(
        sender: row['sender']! as String,
        dateTime: DateTime.fromMillisecondsSinceEpoch(
          row['received_at']! as int,
        ),
        body: row['body']! as String,
      );
      batch.update(
        tableName,
        {'message_key': messageKey},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
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
          await db.execute(
            'CREATE INDEX idx_sms_inbox_status ON $tableName(status)',
          );
          await db.execute(
            'CREATE INDEX idx_sms_inbox_received_at ON $tableName(received_at)',
          );
        },
      ),
    );
  }

  /// Test-only seam for the v3→v4 migration: creates the schema exactly as
  /// it existed at v3 (before `sms_transaction_candidates`), so a test can
  /// seed it and then reopen at [schemaVersion] to exercise [_onUpgrade]
  /// against real rows — mirrors [openV1ForTest]'s role for the v1→v2 step.
  @visibleForTesting
  static Future<Database> openV3ForTest(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onCreate: (db, version) async {
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
        },
      ),
    );
  }

  /// Test-only seam for the v4→v5 migration: creates the schema exactly as
  /// it existed at v4 (before `financial_events`/`sms_financial_event_links`),
  /// so a test can seed it and then reopen at [schemaVersion] to exercise
  /// [_onUpgrade] against real rows — mirrors [openV3ForTest]'s role for the
  /// v3→v4 step.
  @visibleForTesting
  static Future<Database> openV4ForTest(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        singleInstance: false,
        onCreate: (db, version) async {
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
          await _createTransactionCandidatesTable(db);
        },
      ),
    );
  }

  /// Test-only seam for the v5→v6 migration: creates the schema exactly as
  /// it existed at v5 (before the `money_movement_*`/`transaction_status_*`/
  /// `is_own_account_transfer` columns on `financial_events`), so a test can
  /// seed it and then reopen at [schemaVersion] to exercise [_onUpgrade]
  /// against real rows — mirrors [openV4ForTest]'s role for the v4→v5 step.
  @visibleForTesting
  static Future<Database> openV5ForTest(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        singleInstance: false,
        onCreate: (db, version) async {
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
          await _createTransactionCandidatesTable(db);
          await db.execute('''
            CREATE TABLE $financialEventsTableName (
              id TEXT PRIMARY KEY,
              primary_sms_item_id TEXT NOT NULL,
              event_type TEXT NOT NULL,
              role TEXT NOT NULL,
              status TEXT NOT NULL,
              direction TEXT NOT NULL,
              normalized_sender TEXT,
              amount REAL,
              amount_confidence REAL,
              amount_source TEXT,
              amount_ai_evidence TEXT,
              amount_regex_evidence TEXT,
              merchant TEXT,
              merchant_confidence REAL,
              merchant_source TEXT,
              merchant_ai_evidence TEXT,
              merchant_regex_evidence TEXT,
              category_id TEXT,
              category_confidence REAL,
              category_source TEXT,
              subcategory TEXT,
              payment_method TEXT,
              payment_method_confidence REAL,
              payment_method_source TEXT,
              matched_account_id TEXT,
              matched_card_id TEXT,
              account_confidence REAL,
              account_source TEXT,
              event_date INTEGER NOT NULL,
              overall_confidence REAL NOT NULL,
              confidence_level TEXT NOT NULL,
              automation_action TEXT NOT NULL,
              needs_review INTEGER NOT NULL,
              review_reasons TEXT,
              reference_number TEXT,
              linked_transaction_id TEXT,
              linked_event_id TEXT,
              ai_raw_response TEXT,
              ai_model_version TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE $smsFinancialEventLinksTableName (
              id TEXT PRIMARY KEY,
              financial_event_id TEXT NOT NULL,
              sms_item_id TEXT NOT NULL,
              link_type TEXT NOT NULL,
              confidence REAL NOT NULL,
              linked_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
  }

  /// Test-only seam for the v6→v7 migration: creates the schema exactly as
  /// it existed at v6 (before the `payment_provider_*`/`merchant_type_*`
  /// columns on `financial_events`), so a test can seed it and then reopen
  /// at [schemaVersion] to exercise [_onUpgrade] against real rows —
  /// mirrors [openV5ForTest]'s role for the v5→v6 step.
  @visibleForTesting
  static Future<Database> openV6ForTest(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        singleInstance: false,
        onCreate: (db, version) async {
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
          await _createTransactionCandidatesTable(db);
          await db.execute('''
            CREATE TABLE $financialEventsTableName (
              id TEXT PRIMARY KEY,
              primary_sms_item_id TEXT NOT NULL,
              event_type TEXT NOT NULL,
              role TEXT NOT NULL,
              status TEXT NOT NULL,
              direction TEXT NOT NULL,
              normalized_sender TEXT,
              amount REAL,
              amount_confidence REAL,
              amount_source TEXT,
              amount_ai_evidence TEXT,
              amount_regex_evidence TEXT,
              merchant TEXT,
              merchant_confidence REAL,
              merchant_source TEXT,
              merchant_ai_evidence TEXT,
              merchant_regex_evidence TEXT,
              category_id TEXT,
              category_confidence REAL,
              category_source TEXT,
              subcategory TEXT,
              payment_method TEXT,
              payment_method_confidence REAL,
              payment_method_source TEXT,
              matched_account_id TEXT,
              matched_card_id TEXT,
              account_confidence REAL,
              account_source TEXT,
              money_movement_value INTEGER,
              money_movement_confidence REAL,
              money_movement_source TEXT,
              money_movement_regex_evidence TEXT,
              transaction_status_value TEXT,
              transaction_status_confidence REAL,
              transaction_status_source TEXT,
              is_own_account_transfer INTEGER NOT NULL DEFAULT 0,
              event_date INTEGER NOT NULL,
              overall_confidence REAL NOT NULL,
              confidence_level TEXT NOT NULL,
              automation_action TEXT NOT NULL,
              needs_review INTEGER NOT NULL,
              review_reasons TEXT,
              reference_number TEXT,
              linked_transaction_id TEXT,
              linked_event_id TEXT,
              ai_raw_response TEXT,
              ai_model_version TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE $smsFinancialEventLinksTableName (
              id TEXT PRIMARY KEY,
              financial_event_id TEXT NOT NULL,
              sms_item_id TEXT NOT NULL,
              link_type TEXT NOT NULL,
              confidence REAL NOT NULL,
              linked_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
  }

  /// Test-only seam for the v7→v8 migration: creates the schema exactly as
  /// it existed at v7 (before `merchant_learning_profiles`/
  /// `merchant_learning_corrections`), so a test can seed it and then reopen
  /// at [schemaVersion] to exercise [_onUpgrade] against real rows — mirrors
  /// [openV6ForTest]'s role for the v6→v7 step. `financial_events`'s shape at
  /// v7 is identical to today's, so this reuses [_createFinancialEventsTable]
  /// directly instead of duplicating its columns a fourth time.
  @visibleForTesting
  static Future<Database> openV7ForTest(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        singleInstance: false,
        onCreate: (db, version) async {
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
          await _createTransactionCandidatesTable(db);
          await _createFinancialEventsTable(db);
          await _createSmsFinancialEventLinksTable(db);
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
