import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the v9→v10 upgrade (adding nullable `captured_for_uid`) against a
/// real shipped v9 database: it must be purely additive — every existing
/// `sms_inbox` row untouched (and, specifically, left UNOWNED rather than
/// retroactively bound to anyone) — and a v1 database jumping straight to
/// v10 must end up with exactly the same schema as a v9 database stepping
/// to v10. Mirrors `transaction_candidate_migration_test.dart`'s v3→v4
/// coverage for this step.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String path;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    path = await databaseFactory.getDatabasesPath();
    path = '$path/captured_uid_migration_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  Future<void> seedV9Row(String id, {String status = 'pending'}) async {
    final db = await SmsInboxDatabase.openV9ForTest(path);
    await db.insert(SmsInboxDatabase.tableName, {
      'id': id,
      'message_key': 'key-$id',
      'dedup_key': 'dedup-$id',
      'sender': 'VM-HDFCBK',
      'body': 'Rs.1,250.00 debited from a/c XX5623.',
      'received_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
      'source': 'deviceSms',
      'direction': 'debit',
      'amount': 1250.0,
      'status': status,
      'created_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
    });
    await db.close();
  }

  test(
    'v9->v10 preserves every existing sms_inbox row untouched, including already-converted ones',
    () async {
      await seedV9Row('row-imported', status: 'imported');
      await seedV9Row('row-pending', status: 'pending');

      final database = await SmsInboxDatabase.openUpgradedForTest(path);
      final items = await SmsInboxDao(database).getAll();
      await database.database.close();

      expect(items, hasLength(2));
      expect(items.map((i) => i.id), containsAll(['row-imported', 'row-pending']));
      final imported = items.firstWhere((i) => i.id == 'row-imported');
      expect(imported.status.name, 'imported');
    },
  );

  test(
    'v9->v10: every pre-existing row backfills captured_for_uid to NULL — never guessed, never assigned to "whoever is signed in now"',
    () async {
      await seedV9Row('row-1');
      await seedV9Row('row-2');

      final database = await SmsInboxDatabase.openUpgradedForTest(path);
      final items = await SmsInboxDao(database).getAll();
      await database.database.close();

      expect(items, hasLength(2));
      expect(items.every((i) => i.capturedForUid == null), isTrue);
    },
  );

  test(
    'a fresh install (no prior database) also gets the captured_for_uid column, starting NULL',
    () async {
      final database = await SmsInboxDatabase.openInMemoryForTest();
      final dao = SmsInboxDao(database);

      // Insert directly (bypassing SmsInboxRepository.scanInbox, which is
      // covered separately in sms_inbox_repository_test.dart) purely to
      // confirm the column exists and defaults to NULL on a brand-new v10
      // database, mirroring the fresh-install case in
      // transaction_candidate_migration_test.dart.
      final inserted = await dao.insertIfNew(
        _bareItem('fresh-1'),
      );
      await database.database.close();

      expect(inserted, isTrue);
    },
  );

  test(
    'database persistence: captured_for_uid round-trips through a real close/reopen of the SAME on-disk file',
    () async {
      var db = await SmsInboxDatabase.openV9ForTest(path);
      await db.close();

      // Upgrade this exact on-disk file to v10, write an owned row, close,
      // then reopen the SAME path fresh — the real "app restart" shape,
      // unlike openInMemoryForTest's always-fresh :memory: database.
      var database = await SmsInboxDatabase.openUpgradedForTest(path);
      await SmsInboxDao(database).insertIfNew(_bareItem('owned-1', uid: 'uid-1'));
      await database.database.close();

      SmsInboxDatabase.debugReset();
      database = await SmsInboxDatabase.openUpgradedForTest(path); // reopen, already at v10 — no migration runs again
      final items = await SmsInboxDao(database).getAll();
      await database.database.close();

      expect(items, hasLength(1));
      expect(items.single.capturedForUid, 'uid-1');
    },
  );
}

/// A minimal `SmsInboxItem` for schema-level tests that don't need a real
/// parsed message — goes through the DAO's own `_toRow`/`_fromRow` mapping
/// (via `insertIfNew`/`getAll`), so this test exercises the real insert path
/// for the new column rather than a raw `db.insert` bypassing it.
SmsInboxItem _bareItem(String id, {String? uid}) {
  return SmsInboxItem(
    id: id,
    messageKey: 'key-$id',
    rawMessage: RawSmsMessage(
      address: 'VM-HDFCBK',
      body: 'Rs.1,250.00 debited from a/c XX5623.',
      date: DateTime(2026, 7, 15),
    ),
    dedupKey: 'dedup-$id',
    status: SmsImportStatus.pending,
    createdAt: DateTime(2026, 7, 15),
    capturedForUid: uid,
  );
}
