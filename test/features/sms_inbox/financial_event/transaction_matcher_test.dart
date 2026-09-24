import 'package:finance_app/features/sms_inbox/data/financial_event_dao.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_action.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_evidence_link.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_status.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsInboxDatabase database;
  late FinancialEventDao dao;
  late TransactionMatcher matcher;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    database = await SmsInboxDatabase.openInMemoryForTest();
    dao = FinancialEventDao(database);
    matcher = TransactionMatcher(dao);
  });

  tearDown(() async {
    await database.database.close();
  });

  FinancialEvent event({
    required String id,
    double amount = 500,
    String? referenceNumber,
    String? normalizedSender = 'HDFCBK',
    DateTime? eventDate,
    FinancialEventType eventType = FinancialEventType.payment,
    FinancialEventRole role = FinancialEventRole.standalone,
    bool moneyMovement = true,
  }) {
    return FinancialEvent(
      id: id,
      primarySmsItemId: '$id-sms',
      eventType: eventType,
      role: role,
      status: FinancialEventStatus.pendingReview,
      direction: SmsTransactionDirection.debit,
      amount: FieldConfidence(
        value: amount,
        confidence: 0.85,
        source: EvidenceSource.regexOnly,
      ),
      merchant: const FieldConfidence.unknown(),
      category: const FieldConfidence.unknown(),
      paymentMethod: const FieldConfidence<PaymentMethod>.unknown(),
      accountMatch: const FieldConfidence(
        value: 'acc-1',
        confidence: 1.0,
        source: EvidenceSource.regexOnly,
      ),
      moneyMovement: FieldConfidence(
        value: moneyMovement,
        confidence: 0.85,
        source: EvidenceSource.regexOnly,
      ),
      transactionStatus: const FieldConfidence.unknown(),
      normalizedSender: normalizedSender,
      eventDate: eventDate ?? DateTime(2026, 7, 15, 10),
      overallConfidence: 0.8,
      confidenceLevel: ConfidenceLevel.high,
      automationAction: AutomationAction.needsReview,
      needsReview: false,
      reviewReasons: const [],
      createdAt: DateTime(2026, 7, 15),
      referenceNumber: referenceNumber,
    );
  }

  Future<void> persist(FinancialEvent e, {String? smsItemId}) async {
    await dao.upsert(e);
    await dao.linkSms(
      FinancialEventEvidenceLink(
        id: '${e.id}-link',
        financialEventId: e.id,
        smsItemId: smsItemId ?? e.primarySmsItemId,
        linkType: FinancialEventLinkType.newEvent,
        confidence: e.overallConfidence,
        linkedAt: e.createdAt,
      ),
    );
  }

  test('no existing events at all -> newEvent', () async {
    final outcome = await matcher.match(
      event(id: 'evt-1', referenceNumber: 'REF1'),
    );
    expect(outcome.result, FinancialEventMatchResult.newEvent);
    expect(outcome.matchedEventId, isNull);
  });

  test(
    'same reference number and amount as an existing event -> existingEvent',
    () async {
      await persist(event(id: 'evt-1', referenceNumber: 'REF1', amount: 500));

      final outcome = await matcher.match(
        event(id: 'evt-2', referenceNumber: 'REF1', amount: 500),
      );

      expect(outcome.result, FinancialEventMatchResult.existingEvent);
      expect(outcome.matchedEventId, 'evt-1');
    },
  );

  test(
    'same reference number but a different amount -> possibleDuplicate, never silently merged',
    () async {
      await persist(event(id: 'evt-1', referenceNumber: 'REF1', amount: 500));

      final outcome = await matcher.match(
        event(id: 'evt-2', referenceNumber: 'REF1', amount: 750),
      );

      expect(outcome.result, FinancialEventMatchResult.possibleDuplicate);
      expect(outcome.matchedEventId, 'evt-1');
    },
  );

  test(
    'AI-flagged refund matching an original charge on sender+amount -> refundOfExisting',
    () async {
      await persist(
        event(
          id: 'evt-1',
          amount: 500,
          role: FinancialEventRole.originalCharge,
          eventDate: DateTime(2026, 7, 1),
        ),
      );

      final candidate = event(
        id: 'evt-2',
        amount: 500,
        eventType: FinancialEventType.refund,
        eventDate: DateTime(2026, 7, 20),
      );
      final outcome = await matcher.match(
        candidate,
        isLikelyRefundOrReversal: true,
      );

      expect(outcome.result, FinancialEventMatchResult.refundOfExisting);
      expect(outcome.matchedEventId, 'evt-1');
    },
  );

  test(
    'PHASE 5 (Part 11 — duplicate vs. related): a refund sharing the exact same sender+amount as the '
    'original charge is never collapsed into a duplicate/existingEvent, even though those signals alone '
    'look identical to a genuine duplicate representation of the same event',
    () async {
      await persist(
        event(
          id: 'evt-original',
          amount: 1000,
          role: FinancialEventRole.originalCharge,
          eventDate: DateTime(2026, 7, 1, 10),
        ),
      );

      // Same sender, same amount, close in time — exactly the shape
      // `_matchWeakSignal` would otherwise flag as `possibleDuplicate`.
      // `isLikelyRefundOrReversal` here mirrors how the real pipeline
      // derives it deterministically from the reconciled `eventType`
      // (see `sms_inbox_providers.dart`), not only from an AI opinion.
      final refundCandidate = event(
        id: 'evt-refund',
        amount: 1000,
        eventType: FinancialEventType.refund,
        eventDate: DateTime(2026, 7, 1, 10, 5),
      );
      final outcome = await matcher.match(
        refundCandidate,
        isLikelyRefundOrReversal:
            refundCandidate.eventType == FinancialEventType.refund ||
            refundCandidate.eventType == FinancialEventType.reversal,
      );

      expect(
        outcome.result,
        FinancialEventMatchResult.refundOfExisting,
        reason:
            'a refund is a different financial event from the original purchase — related, never a duplicate representation of it',
      );
      expect(outcome.matchedEventId, 'evt-original');
    },
  );

  test(
    'AI-flagged reversal matching an original charge -> reversalOfExisting',
    () async {
      await persist(
        event(
          id: 'evt-1',
          amount: 500,
          role: FinancialEventRole.originalCharge,
          eventDate: DateTime(2026, 7, 1),
        ),
      );

      final candidate = event(
        id: 'evt-2',
        amount: 500,
        eventType: FinancialEventType.reversal,
        eventDate: DateTime(2026, 7, 20),
      );
      final outcome = await matcher.match(
        candidate,
        isLikelyRefundOrReversal: true,
      );

      expect(outcome.result, FinancialEventMatchResult.reversalOfExisting);
    },
  );

  test(
    'same sender+amount within a few hours, no reference number -> possibleDuplicate',
    () async {
      await persist(
        event(
          id: 'evt-1',
          amount: 500,
          eventDate: DateTime(2026, 7, 15, 10, 0),
        ),
      );

      final outcome = await matcher.match(
        event(
          id: 'evt-2',
          amount: 500,
          eventDate: DateTime(2026, 7, 15, 12, 0),
        ),
      );

      expect(outcome.result, FinancialEventMatchResult.possibleDuplicate);
    },
  );

  test(
    'same sender+amount but many hours apart -> treated as a genuinely separate newEvent',
    () async {
      await persist(
        event(
          id: 'evt-1',
          amount: 500,
          eventDate: DateTime(2026, 7, 15, 10, 0),
        ),
      );

      final outcome = await matcher.match(
        event(
          id: 'evt-2',
          amount: 500,
          eventDate: DateTime(2026, 7, 16, 10, 0),
        ),
      );

      expect(outcome.result, FinancialEventMatchResult.newEvent);
    },
  );

  test(
    'a real payment resolves an earlier reminder with the same sender+amount -> resolvesPriorEvent',
    () async {
      await persist(
        event(
          id: 'reminder-1',
          amount: 8500,
          eventType: FinancialEventType.reminder,
          moneyMovement: false,
          eventDate: DateTime(2026, 7, 1),
        ),
      );

      final realPayment = event(
        id: 'evt-2',
        amount: 8500,
        eventType: FinancialEventType.loanEmi,
        eventDate: DateTime(2026, 7, 5),
      );
      final outcome = await matcher.match(realPayment);

      expect(outcome.result, FinancialEventMatchResult.resolvesPriorEvent);
      expect(outcome.matchedEventId, 'reminder-1');
    },
  );

  test(
    'a successful retry resolves an earlier failed attempt with the same sender+amount -> resolvesPriorEvent',
    () async {
      await persist(
        event(
          id: 'failed-1',
          amount: 500,
          moneyMovement: false,
          eventDate: DateTime(2026, 7, 15, 9, 0),
        ),
      );

      final retry = event(
        id: 'evt-2',
        amount: 500,
        eventDate: DateTime(2026, 7, 15, 9, 5),
      );
      final outcome = await matcher.match(retry);

      expect(outcome.result, FinancialEventMatchResult.resolvesPriorEvent);
      expect(outcome.matchedEventId, 'failed-1');
    },
  );

  test(
    'resolving a prior event does not touch the prior event itself — it stays exactly as it was',
    () async {
      final reminder = event(
        id: 'reminder-1',
        amount: 8500,
        moneyMovement: false,
        eventDate: DateTime(2026, 7, 1),
      );
      await persist(reminder);

      final realPayment = event(
        id: 'evt-2',
        amount: 8500,
        eventDate: DateTime(2026, 7, 5),
      );
      await matcher.match(realPayment);

      final reloaded = await dao.getById('reminder-1');
      expect(reloaded!.moneyMovement.value, isFalse);
      expect(reloaded.eventType, reminder.eventType);
    },
  );

  test(
    'a reminder or failed candidate never matches anything itself — it always becomes its own newEvent',
    () async {
      // Two reminders about the same EMI, same sender/amount — the matcher
      // does not attempt to dedupe reminders against each other; only a
      // *real* transaction looks backward to resolve one.
      await persist(
        event(
          id: 'reminder-1',
          amount: 8500,
          moneyMovement: false,
          eventDate: DateTime(2026, 7, 1),
        ),
      );

      final secondReminder = event(
        id: 'reminder-2',
        amount: 8500,
        moneyMovement: false,
        eventDate: DateTime(2026, 7, 1, 1),
      );
      final outcome = await matcher.match(secondReminder);

      expect(outcome.result, FinancialEventMatchResult.newEvent);
    },
  );

  test(
    'a real transaction is never flagged as a possible duplicate of an earlier reminder/failed event with the same sender+amount',
    () async {
      // Same sender+amount+narrow window as the possibleDuplicate weak-signal
      // test above, but the earlier event has no money movement — this must
      // resolve it (resolvesPriorEvent), never possibleDuplicate.
      await persist(
        event(
          id: 'failed-1',
          amount: 500,
          moneyMovement: false,
          eventDate: DateTime(2026, 7, 15, 10, 0),
        ),
      );

      final outcome = await matcher.match(
        event(
          id: 'evt-2',
          amount: 500,
          eventDate: DateTime(2026, 7, 15, 10, 30),
        ),
      );

      expect(outcome.result, FinancialEventMatchResult.resolvesPriorEvent);
    },
  );

  test(
    'ORPHAN-DUPLICATE REGRESSION: deleting the first-linked SMS never orphans the event or its other links, '
    'and a later SMS sharing the same reference number still finds the same event',
    () async {
      final shared = event(
        id: 'evt-1',
        referenceNumber: 'REF-SHARED',
        amount: 500,
      );
      await dao.upsert(shared);
      // Three physical SMS all describing this one real-world transaction —
      // e.g. a bank alert, a UPI app notification, and a bank confirmation.
      for (final smsId in ['sms-a', 'sms-b', 'sms-c']) {
        await dao.linkSms(
          FinancialEventEvidenceLink(
            id: 'link-$smsId',
            financialEventId: 'evt-1',
            smsItemId: smsId,
            linkType: smsId == 'sms-a'
                ? FinancialEventLinkType.newEvent
                : FinancialEventLinkType.additionalEvidence,
            confidence: 0.8,
            linkedAt: DateTime(2026, 7, 15),
          ),
        );
      }

      // Under the OLD `duplicate_of_id` model, sms-a would have been "the
      // original" — deleting it used to orphan sms-b/sms-c. Here, deleting
      // its link must only remove that one link.
      await dao.deleteLinksForSmsIds(['sms-a']);

      final remainingLinks = await dao.getLinksForEvent('evt-1');
      expect(
        remainingLinks.map((l) => l.smsItemId),
        unorderedEquals(['sms-b', 'sms-c']),
      );

      final stillExists = await dao.getById('evt-1');
      expect(
        stillExists,
        isNotNull,
        reason: 'the event must survive the deletion of any single linked SMS',
      );

      // A later SMS describing the same real-world transaction (same
      // reference number/amount) must find the SAME event — never create a
      // second, disconnected one.
      final laterCandidate = event(
        id: 'evt-2-candidate',
        referenceNumber: 'REF-SHARED',
        amount: 500,
      );
      final outcome = await matcher.match(laterCandidate);

      expect(outcome.result, FinancialEventMatchResult.existingEvent);
      expect(outcome.matchedEventId, 'evt-1');

      final allEvents = await dao.getAll();
      expect(
        allEvents,
        hasLength(1),
        reason: 'no orphaned second event should ever be created',
      );
    },
  );
}
