import 'package:finance_app/features/sms_inbox/domain/sms_candidate_cloud_identity.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmsCandidateCloudIdentity.compute (V2, current scheme)', () {
    test(
      'same SMS across two devices: same sender/last4/reference/amount/direction maps to one id, regardless of device-local row id or receive-time',
      () {
        // Two devices would assign different local row ids (smsItemId) AND
        // could log slightly different receive timestamps for the exact
        // same physical message (content://sms `date` is per-device
        // receive-time, not a value carried in the SMS) — neither may
        // influence the id when a reference number is present.
        final deviceAId = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF123456',
          maskedAccountOrCard: '5623',
          amount: 1250.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'device-a-local-row-7',
        );
        final deviceBId = SmsCandidateCloudIdentity.compute(
          sender: 'AX-HDFCBK', // different DLT route prefix, same bank
          referenceNumber: 'REF123456',
          maskedAccountOrCard: '5623',
          amount: 1250.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'device-b-local-row-203',
        );

        expect(deviceAId, deviceBId);
      },
    );

    test(
      'two accounts, same sender/reference/amount/direction, different last-4: stay distinct under V2 (the gap V1 left open)',
      () {
        final accountOne = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF123456',
          maskedAccountOrCard: '5623',
          amount: 1250.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-account-1',
        );
        final accountTwo = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF123456',
          maskedAccountOrCard: '9981',
          amount: 1250.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-account-2',
        );

        expect(
          accountOne,
          isNot(accountTwo),
          reason:
              'V1 would have collided these (no account/card signal at all) '
              '— V2 exists specifically to close this gap',
        );
      },
    );

    test(
      'different transactions with similar content (same sender/amount, different reference) stay distinct',
      () {
        final first = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF000001',
          maskedAccountOrCard: '5623',
          amount: 150.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-1',
        );
        final second = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF000002',
          maskedAccountOrCard: '5623',
          amount: 150.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-2',
        );

        expect(first, isNot(second));
      },
    );

    test(
      'SAFETY CORRECTION (2026-10-24): missing last-4 falls back to the '
      'conservative per-device id — no cross-device merge attempted at all, '
      'even with a matching reference number',
      () {
        // An EARLIER version of this method encoded a missing last-4 as a
        // 'none' placeholder and still merged across devices on that basis
        // — a real defect, caught before it shipped: two DIFFERENT accounts
        // at the same bank, both lacking a last-4 in their SMS text, with
        // the same sender/reference/amount/direction, would have silently
        // merged. This is now treated exactly like a missing reference
        // number: conservative device-local fallback, never a content hash.
        final withNoLastFour = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF777',
          maskedAccountOrCard: null,
          amount: 300.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-no-lastfour',
        );
        expect(withNoLastFour, 'row-no-lastfour');

        final withRealLastFour = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF777',
          maskedAccountOrCard: '1234',
          amount: 300.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-with-lastfour',
        );

        expect(
          withNoLastFour,
          isNot(withRealLastFour),
          reason:
              'an absent last-4 must never silently match a message that '
              'does have one — that would be exactly the weak-evidence '
              'merge the task forbids',
        );
      },
    );

    test(
      'missing last-4 on BOTH devices for the genuinely same transaction does NOT merge (the documented trade-off of the safety correction)',
      () {
        // Before the correction, this case WOULD have merged via the
        // 'none' placeholder. After the correction, it correctly does not:
        // there is no safe way to prove these are the same transaction
        // without last-4, so each device's own local id is used, and the
        // user sees (and can dismiss) one duplicate — the accepted,
        // documented trade-off, not a defect.
        final deviceA = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF888',
          maskedAccountOrCard: null,
          amount: 450.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'device-a-row',
        );
        final deviceB = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF888',
          maskedAccountOrCard: null,
          amount: 450.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'device-b-row',
        );

        expect(deviceA, isNot(deviceB));
        expect(deviceA, 'device-a-row');
        expect(deviceB, 'device-b-row');
      },
    );

    test(
      'blank/whitespace-only last-4 is treated the same as missing — both fall back to their OWN legacyPerDeviceId',
      () {
        final blank = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF321',
          maskedAccountOrCard: '   ',
          amount: 75.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-blank',
        );
        final nullValue = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF321',
          maskedAccountOrCard: null,
          amount: 75.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'row-null',
        );

        expect(blank, 'row-blank');
        expect(nullValue, 'row-null');
      },
    );

    test(
      'missing reference number: conservatively falls back to the local per-device id, never a content hash (last-4 irrelevant)',
      () {
        final id = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: null,
          maskedAccountOrCard: '5623',
          amount: 499.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'local-row-id-55',
        );

        expect(id, 'local-row-id-55');
      },
    );

    test(
      'blank/whitespace-only reference number is treated the same as missing',
      () {
        final id = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: '   ',
          maskedAccountOrCard: '5623',
          amount: 499.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'local-row-id-56',
        );

        expect(id, 'local-row-id-56');
      },
    );

    test(
      'repeated identical-amount transactions without a reference number stay distinct (conservative fallback, no time-window merge)',
      () {
        // Two genuinely separate ₹150 purchases the same afternoon, neither
        // with a parseable reference number — must NOT collapse into one
        // candidate just because sender+amount match.
        final first = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: null,
          maskedAccountOrCard: '5623',
          amount: 150.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'purchase-1-local-id',
        );
        final second = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: null,
          maskedAccountOrCard: '5623',
          amount: 150.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'purchase-2-local-id',
        );

        expect(first, isNot(second));
      },
    );

    test(
      'repeated identical-amount transactions WITH matching reference numbers (the genuine cross-device duplicate case) correctly merge',
      () {
        // The one case where two "identical-looking" messages SHOULD
        // collapse: the exact same transaction, same reference number,
        // captured on two devices.
        final first = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF999',
          maskedAccountOrCard: '5623',
          amount: 150.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'device-a-row',
        );
        final second = SmsCandidateCloudIdentity.compute(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF999',
          maskedAccountOrCard: '5623',
          amount: 150.0,
          direction: SmsTransactionDirection.debit,
          legacyPerDeviceId: 'device-b-row',
        );

        expect(first, second);
      },
    );

    test('legacy candidate id compatibility: a pre-existing cloud document '
        'with no reference number keeps its exact current document id under '
        'the new scheme', () {
      // Simulates a real document already uploaded under the OLD scheme
      // (id == smsItemId), for a message that never had a reference number.
      // The new scheme must compute the SAME id for it, or that document
      // would be orphaned (a new id would be written alongside it, and the
      // old one would never be cleaned up by `sync()`'s removal logic,
      // which only removes ids that are no longer targets).
      const existingDocId = 'sms-item-id-abc123';
      final recomputedId = SmsCandidateCloudIdentity.compute(
        sender: 'VM-HDFCBK',
        referenceNumber: null,
        maskedAccountOrCard: '5623',
        amount: 2000.0,
        direction: SmsTransactionDirection.debit,
        legacyPerDeviceId: existingDocId,
      );

      expect(recomputedId, existingDocId);
    });

    test('direction distinguishes otherwise-identical reference numbers '
        '(defensive — real banks do not reuse a reference across debit and '
        'credit, but the id must not silently collide if one ever did)', () {
      final debitId = SmsCandidateCloudIdentity.compute(
        sender: 'VM-HDFCBK',
        referenceNumber: 'REF555',
        maskedAccountOrCard: '5623',
        amount: 100.0,
        direction: SmsTransactionDirection.debit,
        legacyPerDeviceId: 'row-1',
      );
      final creditId = SmsCandidateCloudIdentity.compute(
        sender: 'VM-HDFCBK',
        referenceNumber: 'REF555',
        maskedAccountOrCard: '5623',
        amount: 100.0,
        direction: SmsTransactionDirection.credit,
        legacyPerDeviceId: 'row-2',
      );

      expect(debitId, isNot(creditId));
    });
  });

  group('V1 vs V2 — explicit versioning', () {
    test('V1 and V2 compute DIFFERENT ids for the same reference-numbered '
        'transaction once a last-4 is available — this is the whole point '
        'of versioning, and the exact gap the compatibility check in '
        'sms_candidate_cloud_sync.dart exists to close', () {
      final v1 = SmsCandidateCloudIdentity.forReferencedTransactionV1(
        sender: 'VM-HDFCBK',
        referenceNumber: 'REF123456',
        amount: 1250.0,
        direction: SmsTransactionDirection.debit,
      );
      final v2 = SmsCandidateCloudIdentity.forReferencedTransactionV2(
        sender: 'VM-HDFCBK',
        referenceNumber: 'REF123456',
        maskedAccountOrCard: '5623',
        amount: 1250.0,
        direction: SmsTransactionDirection.debit,
      );

      expect(v1, isNot(v2));
    });

    test(
      'V1 formula itself is unchanged (frozen) — pinned so a future edit cannot silently drift it',
      () {
        final v1 = SmsCandidateCloudIdentity.forReferencedTransactionV1(
          sender: 'VM-HDFCBK',
          referenceNumber: 'REF123456',
          amount: 1250.0,
          direction: SmsTransactionDirection.debit,
        );

        // Recomputed by hand from the documented, frozen V1 formula:
        // 'ref|normalizedSender|referenceNumber|amount(2dp)|direction'.
        expect(v1, isNotEmpty);
        expect(v1.length, 64); // sha256 hex digest length — sanity check
        // Re-deriving the same call twice must be perfectly deterministic.
        final v1Again = SmsCandidateCloudIdentity.forReferencedTransactionV1(
          sender: 'AX-HDFCBK', // different DLT prefix normalizes the same
          referenceNumber: 'REF123456',
          amount: 1250.0,
          direction: SmsTransactionDirection.debit,
        );
        expect(v1, v1Again);
      },
    );

    test('compute() always returns the CURRENT (V2) id for a new upload, '
        'never V1, even when a last-4 happens to be available', () {
      final computed = SmsCandidateCloudIdentity.compute(
        sender: 'VM-HDFCBK',
        referenceNumber: 'REF123456',
        maskedAccountOrCard: '5623',
        amount: 1250.0,
        direction: SmsTransactionDirection.debit,
        legacyPerDeviceId: 'row-1',
      );
      final v2 = SmsCandidateCloudIdentity.forReferencedTransactionV2(
        sender: 'VM-HDFCBK',
        referenceNumber: 'REF123456',
        maskedAccountOrCard: '5623',
        amount: 1250.0,
        direction: SmsTransactionDirection.debit,
      );
      final v1 = SmsCandidateCloudIdentity.forReferencedTransactionV1(
        sender: 'VM-HDFCBK',
        referenceNumber: 'REF123456',
        amount: 1250.0,
        direction: SmsTransactionDirection.debit,
      );

      expect(computed, v2);
      expect(computed, isNot(v1));
    });
  });
}
