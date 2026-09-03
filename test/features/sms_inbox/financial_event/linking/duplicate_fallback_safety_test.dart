import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_engine.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_type.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/event_fixture.dart';

/// Regression coverage for Bug 1 — the weak duplicate-fallback path (below
/// HIGH-confidence-with-reference) must never classify a new purchase as a
/// duplicate of an earlier refund/reversal, or of anything else, purely
/// from amount+merchant+timing when transactionStatus is unresolved.
///
/// Invariant under test: REFUND/REVERSAL MUST NOT BE TURNED INTO A
/// DUPLICATE JUST BECAUSE AMOUNT+MERCHANT+TIME MATCH.
void main() {
  final base = DateTime(2026, 9, 1, 10);

  Future<EventRelationshipEngine> engineWith(List<dynamic> pool) async {
    final repo = InMemoryEventRelationshipRepository();
    for (final e in pool) {
      repo.addEvent(e);
    }
    return EventRelationshipEngine(repo);
  }

  test('1. successful purchase vs successful duplicate still links as duplicate', () async {
    final original = buildEvent(
      id: 'o1', eventDate: base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final duplicateNotification = buildEvent(
      id: 'd1', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([original]);
    final result = await engine.evaluate(candidate: duplicateNotification, id: 'x1');
    expect(result.relationshipType, EventRelationshipType.duplicate);
  });

  test('2. unresolved purchase vs refund must NOT be duplicate', () async {
    final refund = buildEvent(
      id: 'r2', eventDate: base, amount: 500, merchant: 'Swiggy',
      eventType: FinancialEventType.refund, moneyMovement: true,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    );
    final purchase = buildEvent(
      id: 'p2', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: null,
    );
    final engine = await engineWith([refund]);
    final result = await engine.evaluate(candidate: purchase, id: 'x2');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('3. unresolved purchase vs reversal must NOT be duplicate', () async {
    final reversal = buildEvent(
      id: 'r3', eventDate: base, amount: 500, merchant: 'Swiggy',
      eventType: FinancialEventType.reversal, moneyMovement: true,
      transactionStatus: TransactionStatus.reversed,
    );
    final purchase = buildEvent(
      id: 'p3', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: null,
    );
    final engine = await engineWith([reversal]);
    final result = await engine.evaluate(candidate: purchase, id: 'x3');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('4. successful purchase vs refund must NOT be duplicate', () async {
    final refund = buildEvent(
      id: 'r4', eventDate: base, amount: 500, merchant: 'Swiggy',
      eventType: FinancialEventType.refund, moneyMovement: true,
      transactionStatus: TransactionStatus.refunded,
      direction: SmsTransactionDirection.credit,
    );
    final purchase = buildEvent(
      id: 'p4', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([refund]);
    final result = await engine.evaluate(candidate: purchase, id: 'x4');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('5. successful purchase vs reversal must NOT be duplicate', () async {
    final reversal = buildEvent(
      id: 'r5', eventDate: base, amount: 500, merchant: 'Swiggy',
      eventType: FinancialEventType.reversal, moneyMovement: true,
      transactionStatus: TransactionStatus.reversed,
    );
    final purchase = buildEvent(
      id: 'p5', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([reversal]);
    final result = await engine.evaluate(candidate: purchase, id: 'x5');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('6. same merchant + same amount but different transaction meaning must NOT be duplicate', () async {
    // Candidate is unresolved status; target is a resolved successful
    // charge — same merchant/amount/timing alone still is not enough
    // because the candidate never reached explicit success semantics.
    final target = buildEvent(
      id: 't6', eventDate: base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final candidate = buildEvent(
      id: 'c6', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: null,
    );
    final engine = await engineWith([target]);
    final result = await engine.evaluate(candidate: candidate, id: 'x6');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('7. conflicting direction must NOT be duplicate', () async {
    final target = buildEvent(
      id: 't7', eventDate: base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      direction: SmsTransactionDirection.debit,
    );
    final candidate = buildEvent(
      id: 'c7', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
      direction: SmsTransactionDirection.credit,
    );
    final engine = await engineWith([target]);
    final result = await engine.evaluate(candidate: candidate, id: 'x7');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('8. conflicting status must NOT be duplicate', () async {
    final target = buildEvent(
      id: 't8', eventDate: base, amount: 500, merchant: 'Swiggy',
      moneyMovement: true, transactionStatus: TransactionStatus.pending,
    );
    final candidate = buildEvent(
      id: 'c8', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([target]);
    final result = await engine.evaluate(candidate: candidate, id: 'x8');
    expect(result.relationshipType, isNot(EventRelationshipType.duplicate));
  });

  test('9. exact reference number still works as the strong linking signal', () async {
    final original = buildEvent(
      id: 'o9', eventDate: base, amount: 500, merchant: 'Swiggy',
      referenceNumber: 'UTR-Z9', moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    );
    final duplicateNotification = buildEvent(
      id: 'd9', eventDate: base.add(const Duration(minutes: 2)),
      amount: 500, merchant: 'Swiggy', referenceNumber: 'UTR-Z9',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final engine = await engineWith([original]);
    final result = await engine.evaluate(candidate: duplicateNotification, id: 'x9');
    expect(result.relationshipType, EventRelationshipType.duplicate);
    expect(
      result.matchedSignals.any((s) => s.signal.name == 'referenceId'),
      isTrue,
    );
  });
}
