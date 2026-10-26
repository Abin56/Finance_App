// TEMPORARY (Phase D Firestore Emulator verification, 2026-10-24).
//
// Exercises the REAL `SmsCandidateCloudSync` (the production class, not a
// second implementation) against a REAL Firestore Emulator reached from a
// physical Android device — the one thing `fake_cloud_firestore` cannot
// prove (see the long comment at the top of the "tombstone-aware upload"
// group in test/features/sms_inbox/sms_candidate_cloud_sync_test.dart):
// that `_uploadUnlessHandled`'s `runTransaction` is race-safe against a REAL
// backend's optimistic-concurrency retry, not just logically shaped that
// way under a fake.
//
// Run with the Firestore Emulator already running and reachable from the
// device (same LAN, firewall allowing the port), and EMULATOR_HOST pointing
// at this machine's LAN IP:
//
//   firebase emulators:start --only firestore
//   flutter test integration_test/sms_candidate_cloud_sync_emulator_test.dart \
//     -d <device-id> --dart-define=EMULATOR_HOST=192.168.1.37
//
// Writes only to the Firestore Emulator (an in-memory, local-only backend
// with no persistence and no relation to the real `financeapp-585eb`
// project) — never production Firestore. No financial Transaction is ever
// created by anything in this file. Remove this file (and the matching
// debug-only cleartext manifest change) once Phase D emulator verification
// is complete and accepted.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:finance_app/features/sms_inbox/data/notification_capture_adapter.dart';
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
import 'package:finance_app/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Throws on every `add` — real-device equivalent of the existing fake-test
/// "cloud failure leaves local state untouched" case, proving the same
/// guarantee against the real `SmsTransactionCandidateRepository` type.
class _ThrowingCandidateRepository extends SmsTransactionCandidateRepository {
  _ThrowingCandidateRepository(super.collection);

  @override
  Future<void> add(String id, SmsTransactionCandidateCloud entity) {
    throw Exception('simulated network failure');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '',
  );

  late SmsInboxDatabase database;
  late FirebaseFirestore firestore;
  late String testUid;
  late CollectionReference<Map<String, dynamic>> rawCandidateCollection;
  late CollectionReference<Map<String, dynamic>> tombstoneCollection;
  late SmsTransactionCandidateRepository cloudRepository;

  final financialSms = RawSmsMessage(
    address: 'VM-HDFCBK',
    body:
        'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.',
    date: DateTime(2026, 7, 15, 14, 45),
  );

  setUpAll(() async {
    expect(
      emulatorHost,
      isNotEmpty,
      reason:
          'Pass --dart-define=EMULATOR_HOST=<this machine LAN IP>. Never '
          'point this at a real project — see file header.',
    );
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firestore = FirebaseFirestore.instance;
    firestore.useFirestoreEmulator(emulatorHost, 8080);
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
  });

  // A REAL signed-in Firebase user (via the Auth Emulator, anonymous
  // sign-in) — not a hardcoded string — so `firestore.rules`'
  // `isOwner(uid)` (request.auth.uid == uid) is genuinely satisfied, the
  // same as it would be for a real app. A fresh anonymous user per test
  // keeps tests independent; the Auth/Firestore Emulators hold state only
  // for the process lifetime.
  setUp(() async {
    final credential = await FirebaseAuth.instance.signInAnonymously();
    testUid = credential.user!.uid;
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();

    final candidateCollection = firestore
        .collection('users')
        .doc(testUid)
        .collection('smsTransactionCandidates')
        .withConverter<SmsTransactionCandidateCloud>(
          fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
          toFirestore: (c, _) => c.toFirestore(),
        );
    rawCandidateCollection = firestore
        .collection('users')
        .doc(testUid)
        .collection('smsTransactionCandidates');
    cloudRepository = SmsTransactionCandidateRepository(candidateCollection);
    tombstoneCollection = firestore
        .collection('users')
        .doc(testUid)
        .collection('smsCandidateTombstones');
  });

  tearDown(() async {
    await database.database.close();
    await FirebaseAuth.instance.signOut();
  });

  Future<SmsInboxItem> seedPendingCandidate(
    SmsInboxRepository inboxRepository,
    TransactionCandidateDao candidateDao,
    RawSmsMessage message, {
    String? matchedAccountId,
  }) async {
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
        // Propagated (Phase F1 hardening fix) — without this, every
        // candidate in this file fell back to the legacy per-device id,
        // since SmsCandidateCloudIdentity.compute requires a reference
        // number to attempt the V2 (or V1) content-derived id at all. Same
        // bug previously found and fixed in sms_candidate_cloud_sync_test.dart.
        referenceNumber: item.parsed!.referenceNumber,
        matchedAccountId: matchedAccountId,
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

  SmsInboxRepository buildInboxRepository(RawSmsMessage message) =>
      SmsInboxRepository(
        SmsInboxDao(database),
        _FixedReader([message]),
        // This is a real Samsung device with the real SMS Auto Sync feature
        // potentially having captured real RCS notifications — an empty
        // notification reader keeps this harness scoped to exactly the one
        // fixture message, same isolation the fake-backed unit tests get
        // for free from never touching a real platform channel.
        notificationReader: const _EmptyNotificationReader(),
        capturedUidResolver: () => testUid,
        signedInAtResolver: () => DateTime(2000),
      );

  // The V2 (current-scheme) and V1 (legacy) cloud ids `financialSms`
  // computes to — used throughout to assert against the REAL id the
  // production code now writes under, not the stale local-row-id
  // assumption from before Phase F1.
  String v2IdFor(SmsInboxItem item) => SmsCandidateCloudIdentity.forReferencedTransactionV2(
    sender: financialSms.address,
    referenceNumber: item.parsed!.referenceNumber!,
    maskedAccountOrCard: item.parsed!.maskedAccountOrCard!,
    amount: item.parsed!.amount,
    direction: item.parsed!.direction,
  );
  String v1IdFor(SmsInboxItem item) => SmsCandidateCloudIdentity.forReferencedTransactionV1(
    sender: financialSms.address,
    referenceNumber: item.parsed!.referenceNumber!,
    amount: item.parsed!.amount,
    direction: item.parsed!.direction,
  );

  testWidgets('eligible UID-owned candidate uploads successfully', (
    _,
  ) async {
    final candidateDao = TransactionCandidateDao(database);
    final inboxRepository = buildInboxRepository(financialSms);
    final item = await seedPendingCandidate(
      inboxRepository,  
      candidateDao,
      financialSms,
      matchedAccountId: 'acc-1',
    );
    final sync = SmsCandidateCloudSync(
      cloudRepository,
      candidateDao,
      inboxRepository,
      capturedUidResolver: () => testUid,
      tombstoneCollection: tombstoneCollection,
    );

    final result = await sync.sync();

    expect(result.synced, 1);
    expect(result.skippedHandled, 0);
    final cloudDocs = await cloudRepository.getAll();
    expect(cloudDocs, hasLength(1));
    expect(cloudDocs.single.id, v2IdFor(item));
    expect(cloudDocs.single.smsItemId, item.id);
  });

  testWidgets('existing tombstone prevents upload', (_) async {
    final candidateDao = TransactionCandidateDao(database);
    final inboxRepository = buildInboxRepository(financialSms);
    final item = await seedPendingCandidate(
      inboxRepository,
      candidateDao,
      financialSms,
      matchedAccountId: 'acc-1',
    );
    await tombstoneCollection.doc(v2IdFor(item)).set({
      'outcome': 'dismissed',
      'transactionId': null,
      'handledAt': Timestamp.now(),
      'source': 'web',
      'schemaVersion': 1,
    });
    final sync = SmsCandidateCloudSync(
      cloudRepository,
      candidateDao,
      inboxRepository,
      capturedUidResolver: () => testUid,
      tombstoneCollection: tombstoneCollection,
    );

    final result = await sync.sync();

    expect(result.synced, 0);
    expect(result.skippedHandled, 1);
    expect(await cloudRepository.getAll(), isEmpty);
  });

  testWidgets(
    'concurrent tombstone creation during the upload transaction cannot resurrect a handled candidate',
    (_) async {
      // Real race, not simulated: start the upload transaction, and — before
      // it commits — write the tombstone from a second, independent
      // Firestore write (a different client, same emulator backend). If the
      // real transaction's tombstone read genuinely participates in
      // Firestore's optimistic-concurrency contract, the candidate write
      // must never land once the tombstone exists, regardless of ordering.
      final candidateDao = TransactionCandidateDao(database);
      final inboxRepository = buildInboxRepository(financialSms);
      final item = await seedPendingCandidate(
        inboxRepository,
        candidateDao,
        financialSms,
        matchedAccountId: 'acc-1',
      );
      final tombstoneRef = tombstoneCollection.doc(v2IdFor(item));

      // Fire the real upload transaction and the competing tombstone write
      // concurrently — not sequentially — so this actually exercises
      // Firestore's retry-on-conflict behavior rather than a pre-seeded
      // tombstone (already covered by the previous test).
      final sync = SmsCandidateCloudSync(
        cloudRepository,
        candidateDao,
        inboxRepository,
        capturedUidResolver: () => testUid,
        tombstoneCollection: tombstoneCollection,
      );
      final uploadFuture = sync.sync();
      final tombstoneFuture = tombstoneRef.set({
        'outcome': 'imported',
        'transactionId': 'txn-concurrent',
        'handledAt': Timestamp.now(),
        'source': 'web',
        'schemaVersion': 1,
      });
      await Future.wait([uploadFuture, tombstoneFuture]);

      // Whichever order the backend actually serialized them in, the
      // invariant holds either way: once a tombstone exists for this id,
      // the candidate must not exist.
      final tombstoneSnapshot = await tombstoneRef.get();
      expect(tombstoneSnapshot.exists, isTrue);
      final cloudDocs = await rawCandidateCollection.get();
      expect(
        cloudDocs.docs,
        isEmpty,
        reason:
            'a tombstone exists for this id, so no candidate document may '
            'exist, regardless of which write actually "won" the race',
      );
    },
  );

  testWidgets(
    'existing V1 candidate document blocks a new V2 write (real backend, no duplicate V1/V2 pair)',
    (_) async {
      final candidateDao = TransactionCandidateDao(database);
      final inboxRepository = buildInboxRepository(financialSms);
      final item = await seedPendingCandidate(
        inboxRepository,
        candidateDao,
        financialSms,
        matchedAccountId: 'acc-1',
      );
      // Simulates a document already uploaded under the OLD (V1) scheme,
      // written directly against the real emulator — not via the app's own
      // (now V2-only) upload path.
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
      final sync = SmsCandidateCloudSync(
        cloudRepository,
        candidateDao,
        inboxRepository,
        capturedUidResolver: () => testUid,
        tombstoneCollection: tombstoneCollection,
      );

      final result = await sync.sync();

      expect(result.synced, 0, reason: 'must not create a second (V2) doc');
      final cloudDocs = await rawCandidateCollection.get();
      expect(
        cloudDocs.docs.map((d) => d.id),
        [v1IdFor(item)],
        reason: 'only the original V1 document exists — untouched, not duplicated',
      );
    },
  );

  testWidgets(
    'concurrent V1 tombstone creation during a V2 upload transaction cannot resurrect a legacy-handled candidate',
    (_) async {
      // Same real-race shape as the V2-tombstone race test above, but for
      // the LEGACY (V1) tombstone path this hardening adds: start the real
      // upload transaction (which now also reads the V1 tombstone inside
      // the same transaction) and, before it commits, write the V1
      // tombstone from a second, independent write — proving Android's own
      // `runTransaction` genuinely participates in Firestore's
      // optimistic-concurrency contract for the V1 read too, not just the
      // V2 one.
      final candidateDao = TransactionCandidateDao(database);
      final inboxRepository = buildInboxRepository(financialSms);
      final item = await seedPendingCandidate(
        inboxRepository,
        candidateDao,
        financialSms,
        matchedAccountId: 'acc-1',
      );
      final v1TombstoneRef = tombstoneCollection.doc(v1IdFor(item));

      final sync = SmsCandidateCloudSync(
        cloudRepository,
        candidateDao,
        inboxRepository,
        capturedUidResolver: () => testUid,
        tombstoneCollection: tombstoneCollection,
      );
      final uploadFuture = sync.sync();
      final tombstoneFuture = v1TombstoneRef.set({
        'outcome': 'dismissed',
        'transactionId': null,
        'handledAt': Timestamp.now(),
        'source': 'web',
        'schemaVersion': 1,
      });
      await Future.wait([uploadFuture, tombstoneFuture]);

      final v1TombstoneSnapshot = await v1TombstoneRef.get();
      expect(v1TombstoneSnapshot.exists, isTrue);
      final cloudDocs = await rawCandidateCollection.get();
      expect(
        cloudDocs.docs,
        isEmpty,
        reason:
            'a V1 tombstone exists for this underlying transaction, so '
            'neither a V1 nor a V2 candidate document may exist, regardless '
            'of which write actually "won" the race',
      );
    },
  );

  testWidgets('duplicate upload is idempotent', (_) async {
    final candidateDao = TransactionCandidateDao(database);
    final inboxRepository = buildInboxRepository(financialSms);
    await seedPendingCandidate(
      inboxRepository,
      candidateDao,
      financialSms,
      matchedAccountId: 'acc-1',
    );
    final sync = SmsCandidateCloudSync(
      cloudRepository,
      candidateDao,
      inboxRepository,
      capturedUidResolver: () => testUid,
      tombstoneCollection: tombstoneCollection,
    );

    await sync.sync();
    await sync.sync();
    final thirdResult = await sync.sync();

    expect(await cloudRepository.getAll(), hasLength(1));
    expect(thirdResult.synced, 1);
  });

  testWidgets('UID mismatch never uploads', (_) async {
    final candidateDao = TransactionCandidateDao(database);
    final inboxRepository = buildInboxRepository(financialSms);
    await seedPendingCandidate(
      inboxRepository,
      candidateDao,
      financialSms,
      matchedAccountId: 'acc-1',
    );
    // sync built with a DIFFERENT uid than the one the candidate was
    // captured under.
    final sync = SmsCandidateCloudSync(
      cloudRepository,
      candidateDao,
      inboxRepository,
      capturedUidResolver: () => 'some-other-uid',
      tombstoneCollection: tombstoneCollection,
    );

    final result = await sync.sync();

    expect(result.synced, 0);
    expect(await cloudRepository.getAll(), isEmpty);
  });

  testWidgets(
    'network/backend failure preserves local records and never creates a financial transaction',
    (_) async {
      final candidateDao = TransactionCandidateDao(database);
      final inboxRepository = buildInboxRepository(financialSms);
      await seedPendingCandidate(
        inboxRepository,
        candidateDao,
        financialSms,
        matchedAccountId: 'acc-1',
      );
      final localCandidatesBefore = await candidateDao.getAll();
      final localItemsBefore = await inboxRepository.getAll();

      final throwingRepo = _ThrowingCandidateRepository(
        cloudRepository.collection,
      );
      final throwingSync = SmsCandidateCloudSync(
        throwingRepo,
        candidateDao,
        inboxRepository,
        capturedUidResolver: () => testUid,
        // Deliberately no tombstoneCollection: exercises the
        // pre-Phase-D unconditional-`add` path, where the throw happens
        // directly in `add` (the tombstone-aware path's `runTransaction`
        // would also propagate a thrown error the same way — both paths
        // share the requirement that local state is never touched).
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
      expect(localItemsAfter.single.status.name, 'pending');
      // No financial Transaction repository exists anywhere in this file's
      // imports or call graph — nothing in SmsCandidateCloudSync.sync() can
      // create one; this is a structural guarantee, not a runtime check.
    },
  );
}

class _FixedReader extends SmsReaderAdapter {
  _FixedReader(this.messages);
  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
}

class _EmptyNotificationReader extends NotificationCaptureAdapter {
  const _EmptyNotificationReader();

  @override
  Future<List<RawSmsMessage>> readCaptured() async => const [];
}
