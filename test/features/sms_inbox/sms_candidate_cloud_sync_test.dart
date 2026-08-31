import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/sms_transaction_candidate_repository.dart';
import 'package:finance_app/features/sms_inbox/data/transaction_candidate_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_candidate_cloud.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_candidate_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeSmsReaderAdapter extends SmsReaderAdapter {
  _FakeSmsReaderAdapter(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
}

/// Throws on every [add] — stands in for Firestore being unreachable, to
/// prove a cloud failure never touches local storage.
class _ThrowingCandidateRepository extends SmsTransactionCandidateRepository {
  _ThrowingCandidateRepository(super.collection);

  @override
  Future<void> add(String id, SmsTransactionCandidateCloud entity) {
    throw Exception('simulated Firestore outage');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;
  late SmsInboxRepository inboxRepository;
  late TransactionCandidateDao candidateDao;
  late FakeFirebaseFirestore firestore;
  late SmsTransactionCandidateRepository cloudRepository;
  late SmsCandidateCloudSync sync;

  final financialSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body: 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
    date: DateTime(2026, 7, 15, 14, 45),
  );

  void setUpCloud() {
    firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('smsTransactionCandidates').withConverter<SmsTransactionCandidateCloud>(
          fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
          toFirestore: (c, _) => c.toFirestore(),
        );
    cloudRepository = SmsTransactionCandidateRepository(collection);
  }

  /// (Re)points [inboxRepository] at [reader] and rebuilds [sync] against
  /// it — every test needs its own `SmsInboxRepository` (different seeded
  /// messages), so this can't happen once in `setUp`.
  void useReader(_FakeSmsReaderAdapter reader) {
    inboxRepository = SmsInboxRepository(SmsInboxDao(database), reader);
    sync = SmsCandidateCloudSync(cloudRepository, candidateDao, inboxRepository);
  }

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    candidateDao = TransactionCandidateDao(database);
    setUpCloud();
  });

  tearDown(() async {
    await database.database.close();
  });

  /// Scans [message], then builds and stores a minimal local
  /// `TransactionCandidate` for the resulting `SmsInboxItem` directly —
  /// bypassing `AccountCardMatcher`/`TransactionCandidateBuilder` (Phase 1,
  /// already tested on their own) so these tests stay focused on sync
  /// behavior only.
  Future<SmsInboxItem> seedPendingCandidate(RawSmsMessage message, {String? matchedAccountId}) async {
    useReader(_FakeSmsReaderAdapter([message]));
    await inboxRepository.scanInbox();
    final item = (await inboxRepository.getAll()).single;

    await candidateDao.upsert(
      TransactionCandidate(
        id: 'cand-${item.id}',
        smsItemId: item.id,
        amount: item.parsed!.amount,
        direction: item.parsed!.direction,
        eventType: item.parsed!.category,
        transactionDate: item.parsed!.dateTime,
        merchant: item.parsed!.merchantOrSender,
        bankName: item.parsed!.bankName,
        matchedAccountId: matchedAccountId,
        confidenceLevel: matchedAccountId == null ? ConfidenceLevel.low : ConfidenceLevel.high,
        confidenceScore: matchedAccountId == null ? 0.2 : 0.9,
        needsReview: matchedAccountId == null,
        createdAt: DateTime.now(),
      ),
    );
    return item;
  }

  test('uploads exactly one cloud document for a pending, non-duplicate candidate', () async {
    final item = await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');

    final result = await sync.sync();

    expect(result.synced, 1);
    expect(result.removed, 0);
    final cloudDocs = await cloudRepository.getAll();
    expect(cloudDocs, hasLength(1));
    expect(cloudDocs.single.id, item.id);
    expect(cloudDocs.single.accountId, 'acc-1');
  });

  test('the cloud document id is the local SmsInboxItem id, not a random id', () async {
    final item = await seedPendingCandidate(financialSms);
    await sync.sync();

    final cloudDocs = await cloudRepository.getAll();
    expect(cloudDocs.single.id, item.id);
  });

  test('re-syncing repeatedly never creates duplicate cloud documents (idempotent)', () async {
    await seedPendingCandidate(financialSms);

    await sync.sync();
    await sync.sync();
    final secondResult = await sync.sync();

    expect(await cloudRepository.getAll(), hasLength(1));
    expect(secondResult.synced, 1);
    expect(secondResult.removed, 0);
  });

  test('a scan-then-sync cycle run twice does not create duplicate cloud candidates', () async {
    // The exact regression the task calls out: scan -> sync -> scan again ->
    // sync again must not multiply cloud documents. Re-scanning the same
    // physical message is already idempotent locally (UNIQUE message_key),
    // so this mostly proves that idempotency carries through to the cloud
    // side unchanged.
    await seedPendingCandidate(financialSms);
    await sync.sync();

    await inboxRepository.scanInbox(); // re-scan: no new local rows
    await sync.sync();

    expect(await cloudRepository.getAll(), hasLength(1));
  });

  test('removes the cloud document once the SMS is converted (imported)', () async {
    final item = await seedPendingCandidate(financialSms);
    await sync.sync();
    expect(await cloudRepository.getAll(), hasLength(1));

    await inboxRepository.markImported(item.id, linkedEntityId: 'txn-1');
    final result = await sync.sync();

    expect(result.removed, 1);
    expect(await cloudRepository.getAll(), isEmpty);
  });

  test('removes the cloud document once the SMS is ignored', () async {
    final item = await seedPendingCandidate(financialSms);
    await sync.sync();

    await inboxRepository.markIgnored(item.id);
    await sync.sync();

    expect(await cloudRepository.getAll(), isEmpty);
  });

  test('never syncs a flagged duplicate, even if it has a local candidate', () async {
    final resent = RawSmsMessage(
      address: 'AX-HDFCBK',
      body: '${financialSms.body} Download our app!',
      date: financialSms.date,
    );
    useReader(_FakeSmsReaderAdapter([financialSms, resent]));
    await inboxRepository.scanInbox();

    final all = await inboxRepository.getAll();
    final original = all.firstWhere((i) => !i.isDuplicate);
    final duplicate = all.firstWhere((i) => i.isDuplicate);

    for (final item in [original, duplicate]) {
      await candidateDao.upsert(
        TransactionCandidate(
          id: 'cand-${item.id}',
          smsItemId: item.id,
          amount: item.parsed!.amount,
          direction: item.parsed!.direction,
          eventType: item.parsed!.category,
          transactionDate: item.parsed!.dateTime,
          confidenceLevel: ConfidenceLevel.high,
          confidenceScore: 0.9,
          needsReview: false,
          createdAt: DateTime.now(),
        ),
      );
    }

    await sync.sync();

    final cloudDocs = await cloudRepository.getAll();
    expect(cloudDocs, hasLength(1));
    expect(cloudDocs.single.id, original.id);
  });

  test('a cloud failure leaves local candidates and SMS items completely untouched', () async {
    await seedPendingCandidate(financialSms);
    final localCandidatesBefore = await candidateDao.getAll();
    final localItemsBefore = await inboxRepository.getAll();

    final throwingRepo = _ThrowingCandidateRepository(cloudRepository.collection);
    final throwingSync = SmsCandidateCloudSync(throwingRepo, candidateDao, inboxRepository);

    await expectLater(throwingSync.sync(), throwsException);

    final localCandidatesAfter = await candidateDao.getAll();
    final localItemsAfter = await inboxRepository.getAll();
    expect(localCandidatesAfter.map((c) => c.id), localCandidatesBefore.map((c) => c.id));
    expect(localItemsAfter.map((i) => i.id), localItemsBefore.map((i) => i.id));
  });
}
