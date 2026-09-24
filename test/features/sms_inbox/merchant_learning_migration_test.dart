import 'package:finance_app/features/sms_inbox/data/merchant_learning_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the v7->v8 upgrade (adding `merchant_learning_profiles`/
/// `merchant_learning_corrections`) against a real shipped v7 database: it
/// must be purely additive — every existing `sms_inbox` row untouched, and
/// the two new tables immediately usable. Mirrors
/// `financial_event_migration_test.dart`'s role for the v4->v5 step.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String path;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    path = await databaseFactory.getDatabasesPath();
    path =
        '$path/merchant_learning_migration_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  Future<void> seedV7Row(String id) async {
    final db = await SmsInboxDatabase.openV7ForTest(path);
    await db.insert(SmsInboxDatabase.tableName, {
      'id': id,
      'message_key': 'key-$id',
      'dedup_key': 'dedup-$id',
      'sender': 'VM-HDFCBK',
      'body': 'Rs.1,250.00 debited from a/c XX5623.',
      'received_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
      'direction': 'debit',
      'amount': 1250.0,
      'status': 'imported',
      'linked_entity_id': 'txn-99',
      'created_at': DateTime(2026, 7, 15).millisecondsSinceEpoch,
    });
    await db.close();
  }

  test('v7->v8 preserves every existing sms_inbox row untouched', () async {
    await seedV7Row('row-1');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final items = await SmsInboxDao(database).getAll();
    await database.database.close();

    expect(items, hasLength(1));
    expect(items.single.id, 'row-1');
    expect(items.single.linkedEntityId, 'txn-99');
  });

  test('v7->v8 creates usable, empty merchant learning tables', () async {
    await seedV7Row('row-1');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final dao = MerchantLearningDao(database);

    expect(await dao.listProfiles('user-1'), isEmpty);
    expect(await dao.getCorrectionHistory('user-1', 'swiggy'), isEmpty);

    final profile = await dao.getOrCreateProfile('user-1', 'swiggy');
    expect(profile.userId, 'user-1');
    expect(profile.merchantKey, 'swiggy');

    await database.database.close();
  });
}
