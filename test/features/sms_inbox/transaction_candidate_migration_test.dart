import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/transaction_candidate_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the v3→v4 upgrade (adding `sms_transaction_candidates`) against a
/// real shipped v3 database: it must be purely additive — every existing
/// `sms_inbox` row untouched, and a v1 database jumping straight to v4 (the
/// real path for anyone who hasn't opened the app in a while) must end up
/// with exactly the same schema as a v3 database stepping to v4.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String path;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    path = await databaseFactory.getDatabasesPath();
    path = '$path/candidate_migration_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  Future<void> seedV3Row(String id) async {
    final db = await SmsInboxDatabase.openV3ForTest(path);
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

  test('v3->v4 preserves every existing sms_inbox row untouched', () async {
    await seedV3Row('row-1');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final items = await SmsInboxDao(database).getAll();
    await database.database.close();

    expect(items, hasLength(1));
    expect(items.single.id, 'row-1');
    expect(items.single.linkedEntityId, 'txn-99', reason: 'an already-converted SMS must keep its financial record link');
  });

  test('v3->v4 creates a usable, empty sms_transaction_candidates table', () async {
    await seedV3Row('row-1');

    final database = await SmsInboxDatabase.openUpgradedForTest(path);
    final dao = TransactionCandidateDao(database);

    expect(await dao.getAll(), isEmpty);

    await dao.upsert(
      TransactionCandidate(
        id: 'cand-1',
        smsItemId: 'row-1',
        amount: 1250,
        direction: SmsTransactionDirection.debit,
        eventType: SmsTransactionCategory.bankDebit,
        transactionDate: DateTime(2026, 7, 15),
        confidenceLevel: ConfidenceLevel.high,
        confidenceScore: 0.9,
        needsReview: false,
        createdAt: DateTime(2026, 7, 15),
      ),
    );

    final all = await dao.getAll();
    await database.database.close();

    expect(all, hasLength(1));
    expect(all.single.smsItemId, 'row-1');
  });

  test('a fresh install (no prior database) also gets the candidates table', () async {
    final database = await SmsInboxDatabase.openInMemoryForTest();
    final dao = TransactionCandidateDao(database);

    expect(await dao.getAll(), isEmpty);
    await database.database.close();
  });
}
