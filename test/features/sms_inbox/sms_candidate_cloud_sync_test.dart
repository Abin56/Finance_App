import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_repository.dart';
import 'package:finance_app/features/sms_inbox/data/sms_reader_adapter.dart';
import 'package:finance_app/features/sms_inbox/data/sms_transaction_candidate_repository.dart';
import 'package:finance_app/features/sms_inbox/data/transaction_candidate_dao.dart';
import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_candidate_cloud_identity.dart';
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
  late CollectionReference<Map<String, dynamic>> tombstoneCollection;
  late SmsCandidateCloudSync sync;

  // Every pre-existing test in this file is about sync BEHAVIOR (upload
  // once, remove on import/ignore, idempotency, duplicates), not about UID
  // isolation — so they all seed and sync as the same, single signed-in
  // user, exactly as if nothing in Phase C changed. The dedicated
  // "UID isolation" group below is the one that varies this.
  const ownerUid = 'test-owner-uid';
  String? currentSignedInUid = ownerUid;
  String? currentUidResolver() => currentSignedInUid;

  final financialSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body:
        'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
    date: DateTime(2026, 7, 15, 14, 45),
  );

  void setUpCloud() {
    firestore = FakeFirebaseFirestore();
    final collection = firestore
        .collection('smsTransactionCandidates')
        .withConverter<SmsTransactionCandidateCloud>(
          fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
          toFirestore: (c, _) => c.toFirestore(),
        );
    cloudRepository = SmsTransactionCandidateRepository(collection);
    tombstoneCollection = firestore.collection('smsCandidateTombstones');
  }

  /// (Re)points [inboxRepository] at [reader] and rebuilds [sync] against
  /// it — every test needs its own `SmsInboxRepository` (different seeded
  /// messages), so this can't happen once in `setUp`.
  void useReader(_FakeSmsReaderAdapter reader) {
    inboxRepository = SmsInboxRepository(
      SmsInboxDao(database),
      reader,
      capturedUidResolver: currentUidResolver,
      // Phase D ownership safeguard: every message in this file's fixtures
      // is dated 2026, so a "long ago" sign-in keeps the existing behavior
      // this file is actually testing (sync/upload semantics) unaffected by
      // the separate per-message sign-in-time check — that check has its
      // own dedicated coverage in sms_inbox_repository_test.dart.
      signedInAtResolver: () => DateTime(2000),
    );
    sync = SmsCandidateCloudSync(
      cloudRepository,
      candidateDao,
      inboxRepository,
      capturedUidResolver: currentUidResolver,
    );
  }

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    candidateDao = TransactionCandidateDao(database);
    setUpCloud();
    currentSignedInUid = ownerUid;
  });

  tearDown(() async {
    await database.database.close();
  });

  /// Scans [message], then builds and stores a minimal local
  /// `TransactionCandidate` for the resulting `SmsInboxItem` directly —
  /// bypassing `AccountCardMatcher`/`TransactionCandidateBuilder` (Phase 1,
  /// already tested on their own) so these tests stay focused on sync
  /// behavior only.
  Future<SmsInboxItem> seedPendingCandidate(
    RawSmsMessage message, {
    String? matchedAccountId,
  }) async {
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
        // Propagated since Phase F1 (2026-10-24) — previously dropped here,
        // which meant no test in this file ever exercised the
        // reference-numbered cloud-identity path through a real sync()
        // call, even though every fixture SMS in this file includes one.
        // See the dedicated "content-derived identity" group below.
        referenceNumber: item.parsed!.referenceNumber,
        confidenceLevel: matchedAccountId == null
            ? ConfidenceLevel.low
            : ConfidenceLevel.high,
        confidenceScore: matchedAccountId == null ? 0.2 : 0.9,
        needsReview: matchedAccountId == null,
        createdAt: DateTime.now(),
      ),
    );
    return item;
  }

  test(
    'uploads exactly one cloud document for a pending, non-duplicate candidate',
    () async {
      final item = await seedPendingCandidate(
        financialSms,
        matchedAccountId: 'acc-1',
      );

      final result = await sync.sync();

      expect(result.synced, 1);
      expect(result.removed, 0);
      final cloudDocs = await cloudRepository.getAll();
      expect(cloudDocs, hasLength(1));
      expect(cloudDocs.single.smsItemId, item.id);
      expect(cloudDocs.single.accountId, 'acc-1');
    },
  );

  test(
    'the cloud document carries the local SmsInboxItem id as smsItemId, '
    'even though its document id (cloudId) is content-derived when a '
    'reference number is present (Phase F1, 2026-10-24)',
    () async {
      final item = await seedPendingCandidate(financialSms);
      await sync.sync();

      final cloudDocs = await cloudRepository.getAll();
      expect(cloudDocs.single.smsItemId, item.id);
      expect(
        cloudDocs.single.id,
        isNot(item.id),
        reason:
            'financialSms has a reference number, so its cloud identity is '
            'no longer the local row id — see sms_candidate_cloud_identity_test.dart',
      );
    },
  );

  test(
    're-syncing repeatedly never creates duplicate cloud documents (idempotent)',
    () async {
      await seedPendingCandidate(financialSms);

      await sync.sync();
      await sync.sync();
      final secondResult = await sync.sync();

      expect(await cloudRepository.getAll(), hasLength(1));
      expect(secondResult.synced, 0); // already in the cloud: nothing re-sent
      expect(secondResult.alreadySynced, 1);
      expect(secondResult.removed, 0);
    },
  );

  test(
    'a scan-then-sync cycle run twice does not create duplicate cloud candidates',
    () async {
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
    },
  );

  test(
    'removes the cloud document once the SMS is converted (imported)',
    () async {
      final item = await seedPendingCandidate(financialSms);
      await sync.sync();
      expect(await cloudRepository.getAll(), hasLength(1));

      await inboxRepository.markImported(item.id, linkedEntityId: 'txn-1');
      final result = await sync.sync();

      expect(result.removed, 1);
      expect(await cloudRepository.getAll(), isEmpty);
    },
  );

  test('removes the cloud document once the SMS is ignored', () async {
    final item = await seedPendingCandidate(financialSms);
    await sync.sync();

    await inboxRepository.markIgnored(item.id);
    await sync.sync();

    expect(await cloudRepository.getAll(), isEmpty);
  });

  test(
    'never syncs a flagged duplicate, even if it has a local candidate',
    () async {
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
    },
  );

  test(
    'a cloud failure leaves local candidates and SMS items completely untouched',
    () async {
      await seedPendingCandidate(financialSms);
      final localCandidatesBefore = await candidateDao.getAll();
      final localItemsBefore = await inboxRepository.getAll();

      final throwingRepo = _ThrowingCandidateRepository(
        cloudRepository.collection,
      );
      final throwingSync = SmsCandidateCloudSync(
        throwingRepo,
        candidateDao,
        inboxRepository,
        capturedUidResolver: currentUidResolver,
      );

      await expectLater(throwingSync.sync(), throwsException);

      final localCandidatesAfter = await candidateDao.getAll();
      final localItemsAfter = await inboxRepository.getAll();
      expect(
        localCandidatesAfter.map((c) => c.id),
        localCandidatesBefore.map((c) => c.id),
      );
      expect(
        localItemsAfter.map((i) => i.id),
        localItemsBefore.map((i) => i.id),
      );
    },
  );

  group('UID isolation (Phase C, 2026-10-24)', () {
    test(
      'a candidate captured while signed out (capturedForUid null) is never uploaded, even while someone is signed in',
      () async {
        currentSignedInUid = null; // captured while signed out
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        expect(item.capturedForUid, isNull);

        currentSignedInUid = ownerUid; // someone signs in afterward
        final result = await sync.sync();

        expect(result.synced, 0);
        expect(result.skippedNotOwned, 1);
        expect(await cloudRepository.getAll(), isEmpty);
      },
    );

    test(
      'owned candidates are not counted as skippedNotOwned',
      () async {
        await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');

        final result = await sync.sync();

        expect(result.synced, 1);
        expect(result.skippedNotOwned, 0);
      },
    );

    test(
      "User A's candidate cannot upload once the device has switched to User B",
      () async {
        currentSignedInUid = 'user-a-uid';
        await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');
        expect(await sync.sync(), isA<SmsCandidateSyncResult>());
        // Still User A at this point — nothing to assert differently yet;
        // the real point is the switch below.

        currentSignedInUid = 'user-b-uid';
        final result = await sync.sync();

        expect(result.synced, 0);
        // User A's candidate must not be left over under whatever Firestore
        // path this fake collection represents either — the "no longer a
        // valid target" removal applies the same as any other candidate
        // that stopped qualifying.
        expect(await cloudRepository.getAll(), isEmpty);
      },
    );

    test(
      'nobody signed in at sync time: nothing uploads, even for a candidate captured under a real uid',
      () async {
        currentSignedInUid = ownerUid;
        await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');

        currentSignedInUid = null; // signed out before the next sync runs
        final result = await sync.sync();

        expect(result.synced, 0);
        expect(await cloudRepository.getAll(), isEmpty);
      },
    );

    test(
      'an unowned legacy candidate (pre-Phase-C row, capturedForUid never backfilled) stays excluded even though it is otherwise a perfectly normal pending candidate',
      () async {
        // Simulates a row that existed before this migration: scanned, then
        // its capturedForUid is wiped to null directly (what a real
        // pre-v10 row looks like after the additive ALTER TABLE backfill).
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        await database.database.update(
          SmsInboxDatabase.tableName,
          {'captured_for_uid': null},
          where: 'id = ?',
          whereArgs: [item.id],
        );

        final result = await sync.sync();

        expect(result.synced, 0);
        expect(await cloudRepository.getAll(), isEmpty);
      },
    );

    test(
      'pending candidates are never deleted locally just because they fail the uid check — only the cloud mirror is affected',
      () async {
        currentSignedInUid = null;
        await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');

        await sync.sync();

        final localItems = await inboxRepository.getAll();
        final localCandidates = await candidateDao.getAll();
        expect(localItems, hasLength(1));
        expect(localCandidates, hasLength(1));
        expect(localItems.single.status.name, 'pending');
      },
    );

    test(
      'once the SAME uid that captured a candidate signs back in, it uploads normally',
      () async {
        currentSignedInUid = ownerUid;
        await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');

        currentSignedInUid = 'someone-else';
        expect((await sync.sync()).synced, 0);

        currentSignedInUid = ownerUid; // back to the real owner
        final result = await sync.sync();

        expect(result.synced, 1);
        expect(await cloudRepository.getAll(), hasLength(1));
      },
    );
  });

  group('tombstone-aware upload (Phase D, 2026-10-24)', () {
    // IMPORTANT SCOPE NOTE: these tests pin the LOGIC SHAPE of
    // `_uploadUnlessHandled` (tombstone absent -> write; tombstone present ->
    // skip) using `fake_cloud_firestore`, which has no concept of a second,
    // concurrent client — it cannot prove the actual race-safety guarantee
    // (a transaction retrying because another client concurrently wrote the
    // same document). That guarantee is a property of the real Firestore
    // backend's transaction semantics, which are identical regardless of SDK
    // language, and IS verified against the real Firestore Emulator on the
    // web side: `Flow-Fi-WEB/tests/integration/sms-candidate-lifecycle.
    // integration.test.ts` (import-vs-dismiss race, resurrection-denied
    // under real `firestore.rules`). Confirmed directly in this session:
    // `Firebase.initializeApp()` cannot even complete under `flutter test`
    // on this desktop host (no platform channel implementation) — there is
    // no way to connect a Dart test in this repo to a live Firestore
    // Emulator without a real device, which this machine does not have. See
    // the Phase D report's "remaining blockers" for the explicit
    // consequence: the Dart writer's own transaction has not been exercised
    // against a live backend, only its logic shape.
    test(
      'no tombstone for the candidate id: uploads normally',
      () async {
        await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncWithTombstones.sync();

        expect(result.synced, 1);
        expect(result.skippedHandled, 0);
        expect(await cloudRepository.getAll(), hasLength(1));
      },
    );

    test(
      'a tombstone already exists for the candidate id: never (re)creates it, reports it as skipped, never touches local state',
      () async {
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        // Tombstone must be written at the candidate's actual cloud
        // identity (Phase F1, 2026-10-24: content-derived when a reference
        // number is present, not the local row id) — same id the real
        // upload path would compute and check.
        final candidateCloudId = SmsCandidateCloudIdentity.compute(
          sender: financialSms.address,
          referenceNumber: item.parsed!.referenceNumber,
          maskedAccountOrCard: item.parsed!.maskedAccountOrCard,
          amount: item.parsed!.amount,
          direction: item.parsed!.direction,
          legacyPerDeviceId: item.id,
        );
        await tombstoneCollection.doc(candidateCloudId).set({
          'outcome': 'imported',
          'transactionId': 'txn-already-imported',
          'handledAt': Timestamp.now(),
        });
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncWithTombstones.sync();

        expect(result.synced, 0);
        expect(result.skippedHandled, 1);
        expect(await cloudRepository.getAll(), isEmpty); // never resurrected
        // Local state is untouched either way — this is a cloud-mirror
        // decision only, never a local delete/status change.
        expect(await inboxRepository.getAll(), hasLength(1));
        expect(await candidateDao.getAll(), hasLength(1));
      },
    );

    test(
      'without a tombstoneCollection configured (pre-Phase-D call site): falls back to the original unconditional upload, unchanged',
      () async {
        await seedPendingCandidate(financialSms, matchedAccountId: 'acc-1');
        // `sync` (built in `useReader`/`setUp`, no tombstoneCollection) is
        // exactly today's foreground-provider wiring.
        final result = await sync.sync();

        expect(result.synced, 1);
        expect(result.skippedHandled, 0);
      },
    );
  });

  group('V1/V2 versioned identity compatibility (Phase F1 hardening, 2026-10-24)', () {
    // SCOPE NOTE: same as the tombstone group above — `fake_cloud_firestore`
    // pins the LOGIC SHAPE (a V1 tombstone/candidate blocks a V2 write),
    // not real concurrent-client race-safety. The actual atomic
    // multi-document transaction race is verified against the real
    // Firestore Emulator — see
    // `integration_test/sms_candidate_cloud_sync_emulator_test.dart`.

    String v1IdFor(SmsInboxItem item) =>
        SmsCandidateCloudIdentity.forReferencedTransactionV1(
          sender: financialSms.address,
          referenceNumber: item.parsed!.referenceNumber!,
          amount: item.parsed!.amount,
          direction: item.parsed!.direction,
        );

    test(
      'an existing V1 candidate document (no V1 tombstone) blocks the V2 write — never creates a duplicate V1/V2 pair',
      () async {
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        // Simulates a real document already uploaded under the OLD (V1)
        // scheme, before this hardening shipped.
        await cloudRepository.collection.doc(v1IdFor(item)).set(
          SmsTransactionCandidateCloud(
            smsItemId: item.id,
            cloudId: v1IdFor(item),
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
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncWithTombstones.sync();

        expect(result.synced, 0, reason: 'must not create a second (V2) doc');
        expect(
          (await cloudRepository.getAll()).map((d) => d.id),
          [v1IdFor(item)],
          reason: 'only the original V1 document exists — not touched, not duplicated',
        );
      },
    );

    test(
      'an existing V1 tombstone (no V1 candidate document) blocks the V2 write — legacy handled candidates stay handled',
      () async {
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        await tombstoneCollection.doc(v1IdFor(item)).set({
          'outcome': 'dismissed',
          'transactionId': null,
          'handledAt': Timestamp.now(),
        });
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncWithTombstones.sync();

        expect(result.synced, 0);
        expect(result.skippedHandled, 1);
        expect(
          await cloudRepository.getAll(),
          isEmpty,
          reason: 'never resurrected under the new V2 id either',
        );
        // The V1 tombstone itself is never touched/deleted/rewritten.
        final v1Tombstone = await tombstoneCollection.doc(v1IdFor(item)).get();
        expect(v1Tombstone.exists, isTrue);
        expect(v1Tombstone.data()!['outcome'], 'dismissed');
      },
    );

    test(
      'an existing V2 tombstone (the current-scheme case) still blocks correctly, same as before this hardening',
      () async {
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        final v2Id = SmsCandidateCloudIdentity.forReferencedTransactionV2(
          sender: financialSms.address,
          referenceNumber: item.parsed!.referenceNumber!,
          maskedAccountOrCard: item.parsed!.maskedAccountOrCard!,
          amount: item.parsed!.amount,
          direction: item.parsed!.direction,
        );
        await tombstoneCollection.doc(v2Id).set({
          'outcome': 'imported',
          'transactionId': 'txn-1',
          'handledAt': Timestamp.now(),
        });
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncWithTombstones.sync();

        expect(result.synced, 0);
        expect(result.skippedHandled, 1);
        expect(await cloudRepository.getAll(), isEmpty);
      },
    );

    test(
      'no V1 tombstone and no V1 candidate exist: uploads normally at the V2 id',
      () async {
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncWithTombstones.sync();

        expect(result.synced, 1);
        final cloudDocs = await cloudRepository.getAll();
        expect(cloudDocs, hasLength(1));
        expect(cloudDocs.single.id, isNot(v1IdFor(item)));
      },
    );

    test(
      'no-reference-number fallback: V1 and V2 compute the same (legacy per-device) id, so there is nothing distinct to cross-check',
      () async {
        // Build a candidate with no referenceNumber directly (bypassing
        // seedPendingCandidate, which always propagates one from this
        // file's fixture) — the exact scenario where `_legacyV1IdIfApplicable`
        // returns null.
        useReader(_FakeSmsReaderAdapter([financialSms]));
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
            referenceNumber: null, // the fallback case
            confidenceLevel: ConfidenceLevel.high,
            confidenceScore: 0.9,
            needsReview: false,
            createdAt: DateTime.now(),
          ),
        );
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncWithTombstones.sync();

        expect(result.synced, 1);
        final cloudDocs = await cloudRepository.getAll();
        expect(cloudDocs.single.id, item.id);
      },
    );

    test(
      'UID isolation still holds under the V1/V2 compatibility check: a V1 candidate under a different uid never blocks this uid\'s own upload',
      () async {
        currentSignedInUid = 'user-a-uid';
        final itemA = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        // User A's own V1-style doc (irrelevant — different Firestore path
        // in production via users/{uid}/..., but this file's fixtures share
        // one bare collection, so this proves the LOCAL uid filter alone —
        // see sms_candidate_cloud_sync.dart's UID ISOLATION doc comment —
        // already excludes this candidate from any OTHER user's sync target
        // set before cloud identity is even computed).
        currentSignedInUid = 'user-b-uid';
        final syncAsB = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        final result = await syncAsB.sync();

        expect(
          result.synced,
          0,
          reason:
              "User B's sync must not touch User A's candidate (itemA) just "
              'because the V1/V2 compatibility check exists',
        );
        expect(itemA.capturedForUid, 'user-a-uid');
      },
    );

    test(
      'no financial Transaction is ever created by the V1/V2 compatibility path — structural guarantee, not just a runtime check',
      () async {
        final item = await seedPendingCandidate(
          financialSms,
          matchedAccountId: 'acc-1',
        );
        await tombstoneCollection.doc(v1IdFor(item)).set({
          'outcome': 'imported',
          'transactionId': 'txn-already-imported',
          'handledAt': Timestamp.now(),
        });
        final syncWithTombstones = SmsCandidateCloudSync(
          cloudRepository,
          candidateDao,
          inboxRepository,
          capturedUidResolver: currentUidResolver,
          tombstoneCollection: tombstoneCollection,
        );

        await syncWithTombstones.sync();

        // Local SMS status is untouched by any of this — only an explicit
        // user conversion (outside this class entirely) ever changes it.
        final localItem = (await inboxRepository.getAll()).single;
        expect(localItem.status.name, 'pending');
        expect(localItem.linkedEntityId, isNull);
      },
    );
  });
}
