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
import 'package:finance_app/features/sms_inbox/domain/sms_import_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_candidate_cloud.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_candidate_cloud_sync.dart';
import 'package:finance_app/features/sms_inbox/presentation/sms_historical_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeSmsReaderAdapter extends SmsReaderAdapter {
  _FakeSmsReaderAdapter(this.messages);

  final List<RawSmsMessage> messages;

  @override
  Future<List<RawSmsMessage>> readInbox() async => messages;
}

/// Fails `add` for every id in [failingIds] (or every id when null) —
/// stands in for an offline/denied write.
class _FlakyCandidateRepository extends SmsTransactionCandidateRepository {
  _FlakyCandidateRepository(super.collection, {this.failingIds});

  final Set<String>? failingIds;
  int attempts = 0;

  @override
  Future<void> add(String id, SmsTransactionCandidateCloud entity) {
    attempts++;
    if (failingIds == null || failingIds!.contains(id)) {
      throw Exception('simulated Firestore outage');
    }
    return super.add(id, entity);
  }
}

RawSmsMessage _sms(int i) => RawSmsMessage(
  address: 'VM-HDFCBK',
  body:
      'Rs.${100 + i}.00 debited from a/c XX5623 on 15-07-26 to VPA shop$i@icici. Ref No 1234567890${i.toString().padLeft(2, '0')}.',
  date: DateTime(2026, 7, 15, 10, i),
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const uidA = 'uid-account-a';
  const uidB = 'uid-account-b';

  late SmsInboxDatabase database;
  late TransactionCandidateDao candidateDao;
  late FakeFirebaseFirestore firestore;
  String? signedIn;
  bool online = true;

  CollectionReference<SmsTransactionCandidateCloud> candidatesOf(String uid) =>
      firestore
          .collection('users')
          .doc(uid)
          .collection('smsTransactionCandidates')
          .withConverter<SmsTransactionCandidateCloud>(
            fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
            toFirestore: (c, _) => c.toFirestore(),
          );
  CollectionReference<Map<String, dynamic>> tombstonesOf(String uid) =>
      firestore.collection('users').doc(uid).collection('smsCandidateTombstones');

  SmsInboxRepository repo({String? captureAs, List<RawSmsMessage>? messages}) =>
      SmsInboxRepository(
        SmsInboxDao(database),
        _FakeSmsReaderAdapter(messages ?? const []),
        capturedUidResolver: () => captureAs,
        signedInAtResolver: () => DateTime(2000),
      );

  SmsCandidateCloudSync tombstoneAwareSync(String uid) => SmsCandidateCloudSync(
    SmsTransactionCandidateRepository(candidatesOf(uid)),
    candidateDao,
    repo(),
    capturedUidResolver: () => uid,
    tombstoneCollection: tombstonesOf(uid),
  );

  SmsHistoricalRecovery recovery({
    SmsCandidateCloudSync Function(String uid)? cloudSyncFor,
  }) => SmsHistoricalRecovery(
    repo(),
    candidateDao,
    cloudSyncFor: cloudSyncFor ?? tombstoneAwareSync,
    isCloudReachable: (_) async => online,
    capturedUidResolver: () => signedIn,
    uploadTimeout: const Duration(seconds: 5),
  );

  /// Scans [messages] as [captureAs] (null = unowned, like the 237 legacy
  /// rows) and stores a local review candidate for each parsed one.
  Future<List<SmsInboxItem>> seed(
    List<RawSmsMessage> messages, {
    String? captureAs,
  }) async {
    final r = repo(captureAs: captureAs, messages: messages);
    await r.scanInbox();
    final items = await r.getAll();
    final existing = {for (final c in await candidateDao.getAll()) c.smsItemId};
    for (final item in items) {
      if (item.parsed == null || existing.contains(item.id)) continue;
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
          referenceNumber: item.parsed!.referenceNumber,
          confidenceLevel: ConfidenceLevel.low,
          confidenceScore: 0.2,
          needsReview: true,
          createdAt: DateTime(2026, 7, 15),
        ),
      );
    }
    return r.getAll();
  }

  String cloudIdOf(SmsInboxItem item) => SmsCandidateCloudIdentity.compute(
    sender: item.rawMessage.address,
    referenceNumber: item.parsed!.referenceNumber,
    maskedAccountOrCard: item.parsed!.maskedAccountOrCard,
    amount: item.parsed!.amount,
    direction: item.parsed!.direction,
    legacyPerDeviceId: item.id,
  );

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    candidateDao = TransactionCandidateDao(database);
    firestore = FakeFirebaseFirestore();
    signedIn = uidA;
    online = true;
  });

  tearDown(() async {
    await database.database.close();
  });

  group('eligibility', () {
    test('only unowned, pending, non-duplicate rows with a review candidate', () async {
      final unowned = await seed([_sms(1), _sms(2), _sms(3)]);
      await seed([_sms(4)], captureAs: uidB);
      // A re-sent copy of _sms(1) (same time + ref, different trailing
      // text) — stored, but flagged as a duplicate.
      await seed([
        RawSmsMessage(
          address: _sms(1).address,
          body: '${_sms(1).body} T&C apply.',
          date: _sms(1).date,
        ),
      ]);
      await repo().markIgnored(unowned.firstWhere((i) => i.rawMessage.body == _sms(3).body).id);

      final all = await repo().getAll();
      expect(all.where((i) => i.isDuplicate), hasLength(1));

      final eligible = await recovery().eligibleIds();
      expect(eligible, hasLength(2));
      final byId = {for (final i in all) i.id: i};
      for (final id in eligible) {
        expect(byId[id]!.capturedForUid, isNull);
        expect(byId[id]!.status, SmsImportStatus.pending);
        expect(byId[id]!.isDuplicate, isFalse);
      }
    });
  });

  group('run', () {
    test('binds eligible rows to the confirmed account and uploads them to users/{uid}/smsTransactionCandidates', () async {
      final seeded = await seed([_sms(1), _sms(2), _sms(3)]);

      final result = await recovery().run(uidA);

      expect(result.outcome, SmsRecoveryOutcome.completed);
      expect(result.linked, 3);
      expect(result.uploaded, 3);
      expect(result.didUpload, isTrue);
      expect(result.failed, 0);

      final docs = (await candidatesOf(uidA).get()).docs;
      expect(docs.map((d) => d.id).toSet(), seeded.map(cloudIdOf).toSet());
      // Readable in the shape the web Transaction Inbox expects.
      final raw = (await firestore.doc(docs.first.reference.path).get()).data()!;
      expect(raw['source'], 'sms');
      expect(raw.containsKey('deletedAt'), isTrue);
      expect(raw['deletedAt'], isNull);
      expect(raw['smsItemId'], isA<String>());
      expect(docs.first.reference.path, startsWith('users/$uidA/smsTransactionCandidates/'));

      // Local data preserved: same rows, still pending, only ownership set.
      final after = await repo().getAll();
      expect(after, hasLength(3));
      for (final item in after) {
        expect(item.capturedForUid, uidA);
        expect(item.status, SmsImportStatus.pending);
        expect(item.linkedEntityId, isNull);
      }
      expect(await candidateDao.getAll(), hasLength(3));
    });

    test('repeat recovery is idempotent: binds nothing new and creates no duplicate cloud documents', () async {
      await seed([_sms(1), _sms(2)]);
      await recovery().run(uidA);

      final second = await recovery().run(uidA);

      expect(second.linked, 0);
      expect(second.uploaded, 0); // same deterministic ids, already uploaded: nothing re-sent
      expect((await candidatesOf(uidA).get()).docs, hasLength(2));
      expect(await recovery().eligibleIds(), isEmpty);
    });

    test("a different signed-in account cannot claim another account's candidates", () async {
      final ofA = await seed([_sms(1)], captureAs: uidA);
      signedIn = uidB;

      final result = await recovery().run(uidB);

      expect(result.linked, 0);
      expect(result.uploaded, 0);
      expect(result.didUpload, isFalse);
      expect(result.notLinked, 1);
      expect((await repo().getAll()).single.capturedForUid, uidA);
      expect((await candidatesOf(uidB).get()).docs, isEmpty);
      expect((await candidatesOf(uidA).get()).docs, isEmpty);
      expect(ofA.single.capturedForUid, uidA);
    });

    test('mixed device: binds only the unowned rows, never reassigns owned ones', () async {
      await seed([_sms(1)], captureAs: uidB);
      await seed([_sms(2), _sms(3)]);

      final result = await recovery().run(uidA);

      expect(result.linked, 2);
      expect(result.uploaded, 2);
      expect(result.notLinked, 1);
      final owners = (await repo().getAll()).map((i) => i.capturedForUid);
      expect(owners.where((o) => o == uidB), hasLength(1));
      expect(owners.where((o) => o == uidA), hasLength(2));
    });

    test('changes nothing when the signed-in account differs from the confirmed one', () async {
      await seed([_sms(1)]);
      signedIn = uidB;

      final result = await recovery().run(uidA);

      expect(result.outcome, SmsRecoveryOutcome.accountChanged);
      expect((await repo().getAll()).single.capturedForUid, isNull);
      expect((await candidatesOf(uidA).get()).docs, isEmpty);
    });

    test('changes nothing when signed out', () async {
      await seed([_sms(1)]);
      signedIn = null;

      final result = await recovery().run(uidA);

      expect(result.outcome, SmsRecoveryOutcome.notSignedIn);
      expect((await repo().getAll()).single.capturedForUid, isNull);
    });
  });

  group('tombstone protection', () {
    test('a candidate already imported/dismissed on the web (V2 tombstone) is not resurrected', () async {
      final seeded = await seed([_sms(1), _sms(2)]);
      final handled = seeded.first;
      await tombstonesOf(uidA).doc(cloudIdOf(handled)).set({'outcome': 'imported'});

      final result = await recovery().run(uidA);

      expect(result.uploaded, 1);
      expect(result.alreadyHandled, 1);
      final ids = (await candidatesOf(uidA).get()).docs.map((d) => d.id);
      expect(ids, isNot(contains(cloudIdOf(handled))));
    });

    test('a legacy V1 tombstone also blocks the upload', () async {
      final item = (await seed([_sms(1)])).single;
      final v1 = SmsCandidateCloudIdentity.forReferencedTransactionV1(
        sender: item.rawMessage.address,
        referenceNumber: item.parsed!.referenceNumber!,
        amount: item.parsed!.amount,
        direction: item.parsed!.direction,
      );
      await tombstonesOf(uidA).doc(v1).set({'outcome': 'dismissed'});

      final result = await recovery().run(uidA);

      expect(result.uploaded, 0);
      expect(result.alreadyHandled, 1);
      expect(result.didUpload, isFalse);
      expect((await candidatesOf(uidA).get()).docs, isEmpty);
    });

    test('dismiss after recovery: tombstone keeps the candidate out on every later run', () async {
      final item = (await seed([_sms(1)])).single;
      await recovery().run(uidA);
      // Web dismiss: delete candidate + write tombstone.
      await candidatesOf(uidA).doc(cloudIdOf(item)).delete();
      await tombstonesOf(uidA).doc(cloudIdOf(item)).set({'outcome': 'dismissed'});

      final again = await recovery().run(uidA);

      expect(again.uploaded, 0);
      expect(again.alreadyHandled, 1);
      expect((await candidatesOf(uidA).get()).docs, isEmpty);
    });
  });

  group('offline and partial failure', () {
    test('offline: rows are bound, nothing uploaded, and a retry when online uploads them', () async {
      await seed([_sms(1), _sms(2)]);
      online = false;

      final offline = await recovery().run(uidA);

      expect(offline.outcome, SmsRecoveryOutcome.offline);
      expect(offline.linked, 2);
      expect(offline.didUpload, isFalse);
      expect(offline.canRetry, isTrue);
      expect((await candidatesOf(uidA).get()).docs, isEmpty);
      expect(await repo().getAll(), hasLength(2));

      online = true;
      final retry = await recovery().run(uidA);
      expect(retry.linked, 0);
      expect(retry.uploaded, 2);
      expect(retry.canRetry, isFalse);
    });

    test('partial failure is reported per item and the failed ones succeed on retry', () async {
      final seeded = await seed([_sms(1), _sms(2), _sms(3)]);
      final failingId = cloudIdOf(seeded[1]);
      SmsCandidateCloudSync flaky(String uid) => SmsCandidateCloudSync(
        _FlakyCandidateRepository(candidatesOf(uid), failingIds: {failingId}),
        candidateDao,
        repo(),
        capturedUidResolver: () => uid,
      );

      final first = await recovery(cloudSyncFor: flaky).run(uidA);

      expect(first.uploaded, 2);
      expect(first.failed, 1);
      expect(first.canRetry, isTrue);
      expect(await repo().getAll(), hasLength(3));

      final retry = await recovery().run(uidA);
      expect(retry.failed, 0);
      expect((await candidatesOf(uidA).get()).docs, hasLength(3));
    });

    test('stops after 3 consecutive failures and reports the rest as failed', () async {
      await seed([for (var i = 1; i <= 6; i++) _sms(i)]);
      final repository = _FlakyCandidateRepository(candidatesOf(uidA));

      final result = await recovery(
        cloudSyncFor: (uid) => SmsCandidateCloudSync(
          repository,
          candidateDao,
          repo(),
          capturedUidResolver: () => uid,
        ),
      ).run(uidA);

      expect(repository.attempts, 3);
      expect(result.failed, 6);
      expect(result.uploaded, 0);
      expect(result.didUpload, isFalse);
      expect(await repo().getAll(), hasLength(6));
    });

    test('sync() without continueOnUploadError still throws on the first failure', () async {
      await seed([_sms(1)], captureAs: uidA);
      final sync = SmsCandidateCloudSync(
        _FlakyCandidateRepository(candidatesOf(uidA)),
        candidateDao,
        repo(),
        capturedUidResolver: () => uidA,
      );
      await expectLater(sync.sync(), throwsException);
    });
  });

  group('describeSmsRecoveryResult', () {
    test('a zero-upload run never claims an upload', () {
      const results = [
        SmsHistoricalRecoveryResult(outcome: SmsRecoveryOutcome.completed),
        SmsHistoricalRecoveryResult(
          outcome: SmsRecoveryOutcome.completed,
          linked: 3,
          alreadyHandled: 3,
        ),
        SmsHistoricalRecoveryResult(
          outcome: SmsRecoveryOutcome.offline,
          linked: 5,
        ),
        SmsHistoricalRecoveryResult(
          outcome: SmsRecoveryOutcome.completed,
          failed: 4,
        ),
      ];
      for (final r in results) {
        expect(describeSmsRecoveryResult(r), isNot(contains('Uploaded')));
      }
      expect(
        describeSmsRecoveryResult(results[1]),
        contains('Nothing was uploaded'),
      );
    });

    test('reports real counts', () {
      final text = describeSmsRecoveryResult(
        const SmsHistoricalRecoveryResult(
          outcome: SmsRecoveryOutcome.completed,
          linked: 117,
          uploaded: 110,
          alreadyHandled: 5,
          failed: 2,
        ),
      );
      expect(text, contains('Linked 117 messages'));
      expect(text, contains('Uploaded 110 candidates'));
      expect(text, contains('Skipped 5'));
      expect(text, contains('2 uploads failed'));
    });
  });
}
