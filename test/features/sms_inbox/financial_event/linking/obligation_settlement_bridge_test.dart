import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_type.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/match_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/obligation_settlement_bridge.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/financial_obligation.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_date_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_linker.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_recurrence.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_source.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_status.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_type.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/event_fixture.dart';

FinancialObligation _obligation({
  required String id,
  required ObligationType type,
  required String merchant,
  required double amount,
  DateTime? dueDate,
}) {
  final now = DateTime(2026, 9, 1);
  return FinancialObligation(
    id: id,
    sourceEventIds: ['sms-$id'],
    obligationType: type,
    title: '$merchant — Due',
    merchant: FieldConfidence<String>(
      value: merchant, confidence: 0.9, source: EvidenceSource.regexOnly,
    ),
    amount: FieldConfidence<double>(
      value: amount, confidence: 0.9, source: EvidenceSource.regexOnly,
    ),
    dueDate: dueDate == null
        ? const ResolvedObligationDate.unknown()
        : ResolvedObligationDate(value: dueDate, kind: ObligationDateKind.dueDate, confidence: 0.9),
    recurrence: ObligationRecurrence.singleObservation(now),
    accountMatch: const FieldConfidence<String>.unknown(),
    paymentMethod: const FieldConfidence.unknown(),
    status: ObligationStatus.due,
    confidence: 0.8,
    evidence: const [],
    source: ObligationSource.smsDetected,
    reviewReasons: const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final base = DateTime(2026, 9, 5, 10);
  late InMemoryObligationRepository obligationRepository;
  late ObligationSettlementBridge bridge;

  setUp(() {
    obligationRepository = InMemoryObligationRepository();
    bridge = ObligationSettlementBridge(
      ObligationLinker(obligationRepository),
      getObligation: obligationRepository.getById,
    );
  });

  test('Safety rule 1: a reminder (no money movement) never settles an obligation', () async {
    final reminder = buildEvent(
      id: 'e1', eventDate: base, amount: 8000, merchant: 'HDFC Credit Card',
      moneyMovement: false,
    );
    final result = await bridge.settle(candidate: reminder, id: 'r1');
    expect(result, isNull);
  });

  test('EMI obligation settles as INSTALLMENT_FOR', () async {
    await obligationRepository.upsert(
      _obligation(id: 'obl-emi', type: ObligationType.emiObligation, merchant: 'HDFC Bank', amount: 5000),
    );
    final payment = buildEvent(
      id: 'e2', eventDate: base, amount: 5000, merchant: 'HDFC Bank',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await bridge.settle(candidate: payment, id: 'r2');

    expect(result, isNotNull);
    expect(result!.relationshipType, EventRelationshipType.installmentFor);
    expect(result.targetObligationId, 'obl-emi');
    expect(result.confidence, MatchConfidence.high);
    expect(result.needsReview, isFalse);
  });

  test('loan obligation also settles as INSTALLMENT_FOR', () async {
    await obligationRepository.upsert(
      _obligation(id: 'obl-loan', type: ObligationType.loanObligation, merchant: 'ABC Finance', amount: 8000),
    );
    final payment = buildEvent(
      id: 'e3', eventDate: base, amount: 8000, merchant: 'ABC Finance',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await bridge.settle(candidate: payment, id: 'r3');

    expect(result!.relationshipType, EventRelationshipType.installmentFor);
  });

  test('subscription obligation settles as SUBSCRIPTION_FOR', () async {
    await obligationRepository.upsert(
      _obligation(id: 'obl-netflix', type: ObligationType.subscriptionRenewal, merchant: 'Netflix', amount: 649),
    );
    final payment = buildEvent(
      id: 'e4', eventDate: base, amount: 649, merchant: 'Netflix',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await bridge.settle(candidate: payment, id: 'r4');

    expect(result!.relationshipType, EventRelationshipType.subscriptionFor);
  });

  test('upcoming-debit obligation settles as SCHEDULED_FOR', () async {
    await obligationRepository.upsert(
      _obligation(id: 'obl-sched', type: ObligationType.upcomingDebit, merchant: 'DTH Recharge', amount: 300),
    );
    final payment = buildEvent(
      id: 'e5', eventDate: base, amount: 300, merchant: 'DTH Recharge',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await bridge.settle(candidate: payment, id: 'r5');

    expect(result!.relationshipType, EventRelationshipType.scheduledFor);
  });

  test('generic bill/credit-card due obligation settles as PAYMENT_FOR', () async {
    await obligationRepository.upsert(
      _obligation(id: 'obl-cc', type: ObligationType.creditCardDue, merchant: 'HDFC Credit Card', amount: 10000),
    );
    final payment = buildEvent(
      id: 'e6', eventDate: base, amount: 10000, merchant: 'HDFC Credit Card',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await bridge.settle(candidate: payment, id: 'r6');

    expect(result!.relationshipType, EventRelationshipType.paymentFor);
  });

  test('no outstanding obligation matches -> returns null, never fabricated', () async {
    final payment = buildEvent(
      id: 'e7', eventDate: base, amount: 999, merchant: 'Random Store',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await bridge.settle(candidate: payment, id: 'r7');
    expect(result, isNull);
  });

  test('ambiguous obligation match surfaces as POSSIBLE_MATCH, never auto-settled', () async {
    await obligationRepository.upsert(
      _obligation(id: 'obl-a', type: ObligationType.subscriptionRenewal, merchant: 'Netflix', amount: 649, dueDate: DateTime(2026, 8, 1)),
    );
    await obligationRepository.upsert(
      _obligation(id: 'obl-b', type: ObligationType.subscriptionRenewal, merchant: 'Netflix', amount: 649, dueDate: DateTime(2026, 9, 1)),
    );
    final payment = buildEvent(
      id: 'e8', eventDate: base, amount: 649, merchant: 'Netflix',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await bridge.settle(candidate: payment, id: 'r8');

    expect(result, isNotNull);
    expect(result!.relationshipType, EventRelationshipType.possibleMatch);
    expect(result.needsReview, isTrue);
  });

  test('this bridge never itself marks the obligation resolved — only returns a verdict', () async {
    await obligationRepository.upsert(
      _obligation(id: 'obl-untouched', type: ObligationType.billDue, merchant: 'BESCOM', amount: 1200),
    );
    final payment = buildEvent(
      id: 'e9', eventDate: base, amount: 1200, merchant: 'BESCOM',
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    await bridge.settle(candidate: payment, id: 'r9');

    final stillOutstanding = await obligationRepository.getById('obl-untouched');
    expect(stillOutstanding!.status, ObligationStatus.due);
  });
}
