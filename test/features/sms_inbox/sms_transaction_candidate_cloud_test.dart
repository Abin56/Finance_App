import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_candidate_cloud_identity.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_candidate_cloud.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:finance_app/features/sms_inbox/domain/transaction_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sender = 'VM-HDFCBK';

  TransactionCandidate localCandidate({
    String smsItemId = 'sms-1',
    String? matchedAccountId,
    String? matchedCardId,
    bool needsReview = false,
    List<String> reasons = const [],
    String? referenceNumber = 'REF123',
  }) {
    return TransactionCandidate(
      id: 'cand-1',
      smsItemId: smsItemId,
      amount: 1250.5,
      direction: SmsTransactionDirection.debit,
      eventType: SmsTransactionCategory.creditCardPurchase,
      transactionDate: DateTime(2026, 7, 15, 10),
      merchant: 'Amazon',
      bankName: 'HDFC Bank',
      matchedAccountId: matchedAccountId,
      matchedCardId: matchedCardId,
      referenceNumber: referenceNumber,
      confidenceLevel: ConfidenceLevel.high,
      confidenceScore: 0.92,
      needsReview: needsReview,
      reviewReasons: reasons,
      createdAt: DateTime(2026, 7, 15, 10, 5),
    );
  }

  group('fromLocal', () {
    test(
      'smsItemId always carries the local row id, even when id (cloudId) differs',
      () {
        final cloud = SmsTransactionCandidateCloud.fromLocal(
          localCandidate(smsItemId: 'sms-42'),
          sender: sender,
        );
        expect(cloud.smsItemId, 'sms-42');
      },
    );

    test(
      'id falls back to the local smsItemId when a reference number is present but no last-4 was given (safety correction, 2026-10-24)',
      () {
        // A reference number alone is no longer enough to compute a
        // content-derived (V2) id — a reliable last-4 is also required, or
        // this falls back to the conservative per-device id, same as the
        // no-reference-number case. See SmsCandidateCloudIdentity.compute's
        // doc comment for why: an earlier version used a 'none' placeholder
        // here and still cross-device-merged on it, which could falsely
        // merge two different accounts that both lack a last-4.
        final cloud = SmsTransactionCandidateCloud.fromLocal(
          localCandidate(smsItemId: 'sms-42', referenceNumber: 'REF123'),
          sender: sender,
        );
        expect(cloud.id, 'sms-42');
      },
    );

    test(
      'id is the V2 identity when both a reference number and a last-4 are present',
      () {
        final cloud = SmsTransactionCandidateCloud.fromLocal(
          localCandidate(smsItemId: 'sms-43', referenceNumber: 'REF123'),
          sender: sender,
          rawLastFour: '5623',
        );
        expect(
          cloud.id,
          SmsCandidateCloudIdentity.forReferencedTransactionV2(
            sender: sender,
            referenceNumber: 'REF123',
            maskedAccountOrCard: '5623',
            amount: 1250.5,
            direction: SmsTransactionDirection.debit,
          ),
        );
        expect(
          cloud.id,
          isNot(
            SmsCandidateCloudIdentity.forReferencedTransactionV1(
              sender: sender,
              referenceNumber: 'REF123',
              amount: 1250.5,
              direction: SmsTransactionDirection.debit,
            ),
          ),
          reason: 'fromLocal always builds the current (V2) id, never V1',
        );
      },
    );

    test(
      'id falls back to the local smsItemId when no reference number was parsed (conservative fallback)',
      () {
        final cloud = SmsTransactionCandidateCloud.fromLocal(
          localCandidate(smsItemId: 'sms-42', referenceNumber: null),
          sender: sender,
        );
        expect(cloud.id, 'sms-42');
      },
    );

    test('carries the matched account/card ids through unchanged', () {
      final cloud = SmsTransactionCandidateCloud.fromLocal(
        localCandidate(matchedAccountId: 'acc-1', matchedCardId: 'card-1'),
        sender: sender,
      );
      expect(cloud.accountId, 'acc-1');
      expect(cloud.cardId, 'card-1');
    });

    test(
      'leaves accountId/cardId null when unresolved rather than guessing',
      () {
        final cloud = SmsTransactionCandidateCloud.fromLocal(
          localCandidate(),
          sender: sender,
        );
        expect(cloud.accountId, isNull);
        expect(cloud.cardId, isNull);
      },
    );

    test('carries the raw last-4 hint separately from the matched account', () {
      final cloud = SmsTransactionCandidateCloud.fromLocal(
        localCandidate(),
        sender: sender,
        rawLastFour: '9876',
      );
      expect(cloud.rawLastFour, '9876');
    });

    test('needs-review reasons round-trip as a plain list', () {
      final cloud = SmsTransactionCandidateCloud.fromLocal(
        localCandidate(
          needsReview: true,
          reasons: const [
            'No matching account or card found for this message.',
          ],
        ),
        sender: sender,
      );
      expect(cloud.needsReview, isTrue);
      expect(cloud.needsReviewReasons, [
        'No matching account or card found for this message.',
      ]);
    });

    test('source is always the sms constant', () {
      expect(SmsTransactionCandidateCloud.source, 'sms');
    });
  });

  group('Firestore round-trip', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('toFirestore/fromFirestore preserves every field', () async {
      final collection = firestore
          .collection('smsTransactionCandidates')
          .withConverter<SmsTransactionCandidateCloud>(
            fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
            toFirestore: (c, _) => c.toFirestore(),
          );

      final original = SmsTransactionCandidateCloud.fromLocal(
        localCandidate(
          matchedAccountId: 'acc-1',
          matchedCardId: 'card-1',
          needsReview: true,
          reasons: const ['x'],
        ),
        sender: sender,
        rawLastFour: '1234',
      );
      await collection.doc(original.id).set(original);

      final reloaded = (await collection.doc(original.id).get()).data()!;

      expect(reloaded.smsItemId, original.smsItemId);
      expect(reloaded.amount, original.amount);
      expect(reloaded.direction, original.direction);
      expect(reloaded.eventType, original.eventType);
      expect(reloaded.transactionDate, original.transactionDate);
      expect(reloaded.merchant, original.merchant);
      expect(reloaded.bankName, original.bankName);
      expect(reloaded.rawLastFour, original.rawLastFour);
      expect(reloaded.accountId, original.accountId);
      expect(reloaded.cardId, original.cardId);
      expect(reloaded.referenceNumber, original.referenceNumber);
      expect(reloaded.confidenceLevel, original.confidenceLevel);
      expect(reloaded.confidenceScore, original.confidenceScore);
      expect(reloaded.needsReview, original.needsReview);
      expect(reloaded.needsReviewReasons, original.needsReviewReasons);
    });

    test(
      'privacy: the stored document never contains raw SMS content or a userId field',
      () async {
        final collection = firestore.collection('smsTransactionCandidates');
        final cloud = SmsTransactionCandidateCloud.fromLocal(
          localCandidate(),
          sender: sender,
          rawLastFour: '1234',
        );
        await collection.doc(cloud.id).set(cloud.toFirestore());

        final raw = (await collection.doc(cloud.id).get()).data()!;

        for (final forbiddenKey in [
          'body',
          'rawBody',
          'sender',
          'smsBody',
          'message',
          'userId',
        ]) {
          expect(
            raw.containsKey(forbiddenKey),
            isFalse,
            reason: '$forbiddenKey must never be written to Firestore',
          );
        }
        // The only "account number" fragment ever present is the masked
        // last-4 — never long enough to be a real account/card number.
        final rawLastFour = raw['rawLastFour'] as String?;
        expect(rawLastFour == null || rawLastFour.length <= 4, isTrue);
      },
    );

    test('enum fields serialize as their Dart enum name', () async {
      final collection = firestore.collection('smsTransactionCandidates');
      final cloud = SmsTransactionCandidateCloud.fromLocal(
        localCandidate(),
        sender: sender,
      );
      await collection.doc(cloud.id).set(cloud.toFirestore());

      final raw = (await collection.doc(cloud.id).get()).data()!;
      expect(raw['direction'], 'debit');
      expect(raw['eventType'], 'creditCardPurchase');
      expect(raw['confidenceLevel'], 'high');
      expect(raw['source'], 'sms');
    });
  });
}
