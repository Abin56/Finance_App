import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_message_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeSmsReaderAdapter extends SmsReaderAdapter {
  _FakeSmsReaderAdapter(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
}

/// Guards the v1→v2 upgrade against an existing user's real database. The
/// migration rebuilds the table (SQLite can't drop `UNIQUE(dedup_key)` in
/// place), so it has a genuine chance of losing rows or breaking the link
/// between an already-converted SMS and the financial record it created.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final existing = RawSmsMessage(
    address: 'VM-HDFCBK',
    body: 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
    date: DateTime(2026, 7, 15, 14, 45),
  );

  late String path;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    // A real file: the migration's rename/copy/drop can't be exercised
    // against ":memory:", which sqflite re-creates per connection.
    path = await databaseFactory.getDatabasesPath();
    path = '$path/migration_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  /// Seeds one row in the v1 schema, exactly as a user on the shipped
  /// version would already have.
  Future<void> seedV1({required String id, String status = 'pending', String? linkedEntityId}) async {
    final db = await SmsInboxDatabase.openV1ForTest(path);
    await db.insert(SmsInboxDatabase.tableName, {
      'id': id,
      'dedup_key': 'dedup-$id',
      'sender': existing.address,
      'body': existing.body,
      'received_at': existing.date.millisecondsSinceEpoch,
      'direction': 'debit',
      'amount': 1250.0,
      'merchant': 'swiggy',
      'bank_name': 'HDFC Bank',
      'masked_account': '5623',
      'reference_number': '123456789012',
      'category': 'upiPayment',
      'confidence': 0.9,
      'status': status,
      'linked_entity_id': linkedEntityId,
      'created_at': existing.date.millisecondsSinceEpoch,
    });
    await db.close();
  }

  test('preserves existing rows, their status and their linked financial record', () async {
    await seedV1(id: 'row-1', status: 'imported', linkedEntityId: 'txn-99');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final items = await SmsInboxDao(database).getAll();
    await database.database.close();

    expect(items, hasLength(1));
    expect(items.single.id, 'row-1');
    expect(items.single.status, SmsImportStatus.imported);
    // The link to the already-created transaction must survive — losing it
    // would strand a real financial record from its source SMS.
    expect(items.single.linkedEntityId, 'txn-99');
    expect(items.single.parsed?.amount, 1250.0);
    expect(items.single.isDuplicate, isFalse);
  });

  test('backfills a real message key, so a re-scan recognizes the migrated row', () async {
    await seedV1(id: 'row-1');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final dao = SmsInboxDao(database);

    final migrated = (await dao.getAll()).single;
    expect(
      migrated.messageKey,
      SmsMessageKey.compute(sender: existing.address, dateTime: existing.date, body: existing.body),
      reason: 'a placeholder key would not match the next scan of the same physical message',
    );

    // The real regression this guards: scanning the same device inbox after
    // upgrading must not re-insert the migrated message as a duplicate.
    final repository = SmsInboxRepository(dao, _FakeSmsReaderAdapter([existing]));
    final newCount = await repository.scanInbox();
    final all = await repository.getAll();
    await database.database.close();

    expect(newCount, 0);
    expect(all, hasLength(1));
    expect(all.single.isDuplicate, isFalse);
  });
}
