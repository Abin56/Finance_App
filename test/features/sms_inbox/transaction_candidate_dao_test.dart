import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/transaction_candidate_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late TransactionCandidateDao dao;
  late SmsInboxDatabase database;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    dao = TransactionCandidateDao(database);
  });

  tearDown(() async {
    await database.database.close();
  });

  TransactionCandidate candidate({
    String id = 'cand-1',
    String smsItemId = 'sms-1',
    bool needsReview = false,
    List<String> reasons = const [],
  }) {
    return TransactionCandidate(
      id: id,
      smsItemId: smsItemId,
      amount: 1250,
      direction: SmsTransactionDirection.debit,
      eventType: SmsTransactionCategory.creditCardPurchase,
      transactionDate: DateTime(2026, 7, 15),
      merchant: 'Amazon',
      bankName: 'HDFC Bank',
      matchedAccountId: 'acc-1',
      matchedCardId: 'card-1',
      referenceNumber: 'REF123',
      confidenceLevel: ConfidenceLevel.high,
      confidenceScore: 0.9,
      needsReview: needsReview,
      reviewReasons: reasons,
      createdAt: DateTime(2026, 7, 15, 10),
    );
  }

  test('upsert then getAll round-trips every field', () async {
    await dao.upsert(candidate(reasons: const ['Possible duplicate.', 'Low parser confidence.']));

    final all = await dao.getAll();
    expect(all, hasLength(1));
    final row = all.single;
    expect(row.smsItemId, 'sms-1');
    expect(row.amount, 1250);
    expect(row.direction, SmsTransactionDirection.debit);
    expect(row.eventType, SmsTransactionCategory.creditCardPurchase);
    expect(row.merchant, 'Amazon');
    expect(row.bankName, 'HDFC Bank');
    expect(row.matchedAccountId, 'acc-1');
    expect(row.matchedCardId, 'card-1');
    expect(row.referenceNumber, 'REF123');
    expect(row.confidenceLevel, ConfidenceLevel.high);
    expect(row.reviewReasons, ['Possible duplicate.', 'Low parser confidence.']);
  });

  test('a candidate with no review reasons round-trips as an empty list', () async {
    await dao.upsert(candidate());

    final row = (await dao.getAll()).single;
    expect(row.reviewReasons, isEmpty);
  });

  test('existingSmsItemIds reflects only smsItemIds that already have a candidate', () async {
    await dao.upsert(candidate(id: 'cand-1', smsItemId: 'sms-1'));
    await dao.upsert(candidate(id: 'cand-2', smsItemId: 'sms-2'));

    final existing = await dao.existingSmsItemIds();
    expect(existing, {'sms-1', 'sms-2'});
    expect(existing.contains('sms-3'), isFalse);
  });

  test('getBySmsItemId finds the right row, null when absent', () async {
    await dao.upsert(candidate(smsItemId: 'sms-1'));

    expect((await dao.getBySmsItemId('sms-1'))?.id, 'cand-1');
    expect(await dao.getBySmsItemId('sms-missing'), isNull);
  });

  test('re-upserting for the same smsItemId replaces the previous candidate, not accumulates', () async {
    await dao.upsert(candidate(id: 'cand-1', smsItemId: 'sms-1', needsReview: true));
    await dao.upsert(candidate(id: 'cand-2', smsItemId: 'sms-1', needsReview: false));

    final all = await dao.getAll();
    expect(all, hasLength(1), reason: 'sms_item_id is uniquely indexed — regenerating must not leave a stale row behind');
    expect(all.single.id, 'cand-2');
    expect(all.single.needsReview, isFalse);
  });

  test('deleteBySmsItemIds removes only the matching candidates', () async {
    await dao.upsert(candidate(id: 'cand-1', smsItemId: 'sms-1'));
    await dao.upsert(candidate(id: 'cand-2', smsItemId: 'sms-2'));

    await dao.deleteBySmsItemIds(['sms-1']);

    final all = await dao.getAll();
    expect(all, hasLength(1));
    expect(all.single.smsItemId, 'sms-2');
  });
}
