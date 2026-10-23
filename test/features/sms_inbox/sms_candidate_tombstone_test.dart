import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_candidate_tombstone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('SmsCandidateTombstone.fromFirestore', () {
    test('id comes from the document id, not a stored field', () async {
      final ref = firestore.collection('smsCandidateTombstones').doc('sms-42');
      await ref.set({
        'outcome': 'imported',
        'transactionId': 'txn-1',
        'handledAt': Timestamp.fromDate(DateTime(2026, 10, 23, 9)),
        'source': 'web',
        'schemaVersion': 1,
      });

      final snapshot = await ref.get();
      final tombstone = SmsCandidateTombstone.fromFirestore(snapshot, null);

      expect(tombstone.smsItemId, 'sms-42');
      expect(tombstone.outcome, SmsCandidateTombstoneOutcome.imported);
      expect(tombstone.transactionId, 'txn-1');
      expect(tombstone.handledAt, DateTime(2026, 10, 23, 9));
      expect(tombstone.source, 'web');
      expect(tombstone.schemaVersion, 1);
    });

    test('dismissed outcome carries a null transactionId', () async {
      final ref = firestore.collection('smsCandidateTombstones').doc('sms-7');
      await ref.set({
        'outcome': 'dismissed',
        'transactionId': null,
        'handledAt': Timestamp.fromDate(DateTime(2026, 10, 23, 9)),
        'source': 'web',
        'schemaVersion': 1,
      });

      final tombstone = SmsCandidateTombstone.fromFirestore(
        await ref.get(),
        null,
      );

      expect(tombstone.outcome, SmsCandidateTombstoneOutcome.dismissed);
      expect(tombstone.transactionId, isNull);
    });

    test('missing/unrecognized schemaVersion defaults to 1', () async {
      final ref = firestore.collection('smsCandidateTombstones').doc('sms-8');
      await ref.set({
        'outcome': 'dismissed',
        'handledAt': Timestamp.fromDate(DateTime(2026, 10, 23, 9)),
      });

      final tombstone = SmsCandidateTombstone.fromFirestore(
        await ref.get(),
        null,
      );

      expect(tombstone.schemaVersion, 1);
      expect(tombstone.source, 'web');
    });

    test('throws on an invalid/missing outcome rather than guessing one', () async {
      final ref = firestore.collection('smsCandidateTombstones').doc('sms-9');
      await ref.set({
        'outcome': 'archived',
        'handledAt': Timestamp.fromDate(DateTime(2026, 10, 23, 9)),
      });

      final snapshot = await ref.get();
      expect(
        () => SmsCandidateTombstone.fromFirestore(snapshot, null),
        throwsStateError,
      );
    });
  });
}
