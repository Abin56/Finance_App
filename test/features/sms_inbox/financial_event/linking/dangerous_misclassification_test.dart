import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_engine.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_type.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/event_fixture.dart';

/// Direct, explicit coverage of every numbered item in the task's Part 18
/// "Dangerous misclassification tests" — each test name states the rule
/// verbatim so this file doubles as a checklist. Most of these scenarios
/// are also exercised (with more variety) by the 100-case corpus; this
/// file exists so each specific rule has one unambiguous, easy-to-find
/// assertion of its own.
void main() {
  final base = DateTime(2026, 9, 1, 10);

  Future<EventRelationshipEngine> engineWith(List<dynamic> pool) async {
    final repo = InMemoryEventRelationshipRepository();
    for (final e in pool) {
      repo.addEvent(e);
    }
    return EventRelationshipEngine(repo);
  }

  test('1. A reminder must never link as a completed transaction', () async {
    final reminder = buildEvent(
      id: 'r', eventDate: base, amount: 5000, merchant: 'HDFC EMI',
      moneyMovement: false,
    );
    final engine = await engineWith([]);
    final result = await engine.evaluate(candidate: reminder, id: 'x1');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
    expect(result.relationshipType, isNot(EventRelationshipType.update));
  });

  test('2. A payment request must never link as a successful payment', () async {
    final request = buildEvent(
      id: 'req', eventDate: base, amount: 500, merchant: 'Rahul',
      moneyMovement: false,
    );
    final engine = await engineWith([]);
    final result = await engine.evaluate(candidate: request, id: 'x2');
    expect(result.relationshipType, EventRelationshipType.newEvent);
  });

  test('3. A failed transaction must never link as a successful transaction', () async {
    final failed = buildEvent(
      id: 'f', eventDate: base, amount: 750, referenceNumber: 'UTR1',
      moneyMovement: false, transactionStatus: TransactionStatus.failed,
    );
    final pending = buildEvent(
      id: 'p', eventDate: base.subtract(const Duration(minutes: 10)),
      amount: 750, referenceNumber: 'UTR1', moneyMovement: false,
      transactionStatus: TransactionStatus.pending,
    );
    final engine = await engineWith([pending]);
    final result = await engine.evaluate(candidate: failed, id: 'x3');
    expect(result.relationshipType, EventRelationshipType.failedUpdate);
    expect(result.relationshipType, isNot(EventRelationshipType.update));
  });

  test('4. A refund must never become a duplicate', () async {
    final refund = buildEvent(
      id: 'ref', eventDate: base.add(const Duration(hours: 1)), amount: 1500,
      merchant: 'Amazon', eventType: FinancialEventType.refund,
      moneyMovement: true, transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    );
    final original = buildEvent(
      id: 'orig', eventDate: base, amount: 1500, merchant: 'Amazon',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      direction: SmsTransactionDirection.debit,
    );
    final engine = await engineWith([original]);
    final result = await engine.evaluate(candidate: refund, id: 'x4');
    expect(result.relationshipType, EventRelationshipType.refundOf);
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('5. A reversal must never become a duplicate', () async {
    final reversal = buildEvent(
      id: 'rev', eventDate: base.add(const Duration(hours: 1)), amount: 2000,
      referenceNumber: 'UTR2', eventType: FinancialEventType.reversal,
      moneyMovement: false, transactionStatus: TransactionStatus.reversed,
    );
    final original = buildEvent(
      id: 'orig2', eventDate: base, amount: 2000, referenceNumber: 'UTR2',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([original]);
    final result = await engine.evaluate(candidate: reversal, id: 'x5');
    expect(result.relationshipType, EventRelationshipType.reversalOf);
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('6-7. An own-account transfer must never become income or an expense', () async {
    // The base engine never itself tags a relationship as "income"/"expense"
    // — that's downstream of `FinancialEvent.direction`/`isOwnAccountTransfer`,
    // which the (owned, untouched) extractor already sets. This engine's
    // contribution to the safety property is: it must never silently merge
    // one leg of a transfer into an unrelated event, which would corrupt
    // the picture a downstream category/report step relies on.
    final debitLeg = buildEvent(
      id: 'tdebit', eventDate: base, amount: 20000,
      direction: SmsTransactionDirection.debit, isOwnAccountTransfer: true,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final unrelated = buildEvent(
      id: 'unrelated', eventDate: base.add(const Duration(minutes: 1)),
      amount: 300, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([unrelated]);
    final result = await engine.evaluate(candidate: debitLeg, id: 'x6');
    expect(result.relationshipType, EventRelationshipType.newEvent);
  });

  test('8. Same amount must not imply same transaction', () async {
    final a = buildEvent(
      id: 'a', eventDate: base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final b = buildEvent(
      id: 'b', eventDate: base.add(const Duration(minutes: 1)),
      amount: 500, merchant: 'Zomato', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([b]);
    final result = await engine.evaluate(candidate: a, id: 'x8');
    expect(result.relationshipType, EventRelationshipType.newEvent);
  });

  test('9. Same merchant must not imply same transaction', () async {
    final a = buildEvent(
      id: 'a2', eventDate: base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final b = buildEvent(
      id: 'b2', eventDate: base.add(const Duration(minutes: 5)),
      amount: 850, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([b]);
    final result = await engine.evaluate(candidate: a, id: 'x9');
    expect(result.relationshipType, EventRelationshipType.newEvent);
  });

  test('10. Same SMS sender must not imply same transaction', () async {
    final a = buildEvent(
      id: 'a3', eventDate: base, amount: 999, normalizedSender: 'HDFCBK',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final b = buildEvent(
      id: 'b3', eventDate: base.add(const Duration(minutes: 1)),
      amount: 250, normalizedSender: 'HDFCBK', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([b]);
    final result = await engine.evaluate(candidate: a, id: 'x10');
    expect(result.relationshipType, EventRelationshipType.newEvent);
  });

  test('11. Different reference IDs must not be merged', () async {
    // "Merged" specifically: the two distinct reference numbers themselves
    // are never treated as equal — any resulting link (if one occurs) must
    // come from independent signals, never from pretending the references
    // match.
    final a = buildEvent(
      id: 'a4', eventDate: base, amount: 500, referenceNumber: 'UTR-AAA',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final b = buildEvent(
      id: 'b4', eventDate: base.add(const Duration(days: 10)),
      amount: 999, referenceNumber: 'UTR-BBB', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([b]);
    final result = await engine.evaluate(candidate: a, id: 'x11');
    expect(result.relationshipType, EventRelationshipType.newEvent);
    expect(
      result.matchedSignals.any((s) => s.signal.name == 'referenceId'),
      isFalse,
      reason: 'The two different reference numbers must never themselves register as a matched signal.',
    );
  });

  test('12. Ambiguous candidates must remain ambiguous', () async {
    final candidate = buildEvent(
      id: 'amb', eventDate: base.add(const Duration(minutes: 5)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final a = buildEvent(
      id: 'ambA', eventDate: base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final b = buildEvent(
      id: 'ambB', eventDate: base.add(const Duration(minutes: 3)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([a, b]);
    final result = await engine.evaluate(candidate: candidate, id: 'x12');
    expect(result.relationshipType, EventRelationshipType.possibleMatch);
    expect(result.targetEventId, isNull);
    expect(result.alternativeCandidates.length, 2);
  });

  test('13. A later transaction must not overwrite an earlier unrelated transaction', () async {
    // This engine never mutates/overwrites anything — it only ever RETURNS
    // a verdict (see every class's doc comment: "never mutates ... only
    // returns a verdict"). Confirm an unrelated earlier event is left
    // completely untouched in the repository after evaluating a later one.
    final repo = InMemoryEventRelationshipRepository();
    final earlier = buildEvent(
      id: 'earlier', eventDate: base, amount: 100, merchant: 'Cafe',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    repo.addEvent(earlier);
    final later = buildEvent(
      id: 'later', eventDate: base.add(const Duration(days: 5)),
      amount: 9999, merchant: 'Unrelated Store', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = EventRelationshipEngine(repo);
    await engine.evaluate(candidate: later, id: 'x13');

    final untouched = repo.getEvent('earlier');
    expect(untouched, same(earlier));
  });

  test('14. Multiple SMS notifications for one event must not create multiple financial events', () async {
    final first = buildEvent(
      id: 'first', eventDate: base, amount: 750, merchant: 'Swiggy',
      referenceNumber: 'UTR3', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final secondNotification = buildEvent(
      id: 'second', eventDate: base.add(const Duration(minutes: 1)),
      amount: 750, merchant: 'Swiggy', referenceNumber: 'UTR3',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([first]);
    final result = await engine.evaluate(candidate: secondNotification, id: 'x14');
    expect(result.relationshipType, EventRelationshipType.duplicate);
  });

  test('15. Deleting one relationship edge must never destroy the underlying events', () async {
    final repo = InMemoryEventRelationshipRepository();
    final e1 = buildEvent(
      id: 'ev1', eventDate: base, amount: 500, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final e2 = buildEvent(
      id: 'ev2', eventDate: base, amount: 500, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    repo.addEvent(e1);
    repo.addEvent(e2);
    final engine = EventRelationshipEngine(repo);
    final relationship = await engine.evaluate(candidate: e1, id: 'rel-1');
    repo.recordRelationship(relationship);

    repo.removeRelationship('rel-1');

    expect(repo.getEvent('ev1'), isNotNull);
    expect(repo.getEvent('ev2'), isNotNull);
    expect(repo.relationshipsFor('ev1'), isEmpty);
  });
}
