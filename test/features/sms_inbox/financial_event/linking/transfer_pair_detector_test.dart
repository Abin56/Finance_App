import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_type.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/match_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/transfer_pair_detector.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/event_fixture.dart';

void main() {
  final base = DateTime(2026, 9, 1, 10);
  late InMemoryEventRelationshipRepository repository;
  late TransferPairDetector detector;

  setUp(() {
    repository = InMemoryEventRelationshipRepository();
    detector = TransferPairDetector(repository);
  });

  test('returns null for an event not flagged as an own-account transfer', () async {
    final candidate = buildEvent(
      id: 'e1', eventDate: base, amount: 500,
      transactionStatus: TransactionStatus.success, moneyMovement: true,
    );
    final result = await detector.detect(candidate: candidate, id: 'r1');
    expect(result, isNull);
  });

  test('Safety rules 6-7: pairs the debit and credit legs, neither becomes income or expense', () async {
    final debitLeg = buildEvent(
      id: 'debit', eventDate: base, amount: 20000,
      direction: SmsTransactionDirection.debit, isOwnAccountTransfer: true,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      accountId: 'acc-hdfc',
    );
    final creditLeg = buildEvent(
      id: 'credit', eventDate: base.add(const Duration(minutes: 2)),
      amount: 20000, direction: SmsTransactionDirection.credit,
      isOwnAccountTransfer: true, moneyMovement: true,
      transactionStatus: TransactionStatus.success, accountId: 'acc-sbi',
    );
    repository.addEvent(creditLeg);

    final result = await detector.detect(candidate: debitLeg, id: 'r2');

    expect(result, isNotNull);
    expect(result!.relationshipType, EventRelationshipType.transferPair);
    expect(result.targetEventId, 'credit');
    expect(result.confidence, MatchConfidence.high);
    expect(result.needsReview, isFalse);
  });

  test('a single unpaired leg stays unresolved, never income or expense', () async {
    final candidate = buildEvent(
      id: 'lone', eventDate: base, amount: 20000,
      direction: SmsTransactionDirection.debit, isOwnAccountTransfer: true,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await detector.detect(candidate: candidate, id: 'r3');

    expect(result, isNotNull);
    expect(result!.relationshipType, EventRelationshipType.unknownRelationship);
    expect(result.targetEventId, isNull);
    expect(result.needsReview, isTrue);
  });

  test('multiple candidate counterpart legs never arbitrarily pick one', () async {
    final candidate = buildEvent(
      id: 'debit2', eventDate: base, amount: 5000,
      direction: SmsTransactionDirection.debit, isOwnAccountTransfer: true,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    repository.addEvent(buildEvent(
      id: 'creditA', eventDate: base.add(const Duration(minutes: 1)),
      amount: 5000, direction: SmsTransactionDirection.credit,
      isOwnAccountTransfer: true, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ));
    repository.addEvent(buildEvent(
      id: 'creditB', eventDate: base.add(const Duration(minutes: 3)),
      amount: 5000, direction: SmsTransactionDirection.credit,
      isOwnAccountTransfer: true, moneyMovement: true,
      transactionStatus: TransactionStatus.success,
    ));

    final result = await detector.detect(candidate: candidate, id: 'r4');

    expect(result, isNotNull);
    expect(result!.relationshipType, EventRelationshipType.possibleMatch);
    expect(result.targetEventId, isNull);
    expect(result.alternativeCandidates.length, 2);
    expect(result.needsReview, isTrue);
  });

  test('a candidate with no resolved amount cannot be paired', () async {
    final candidate = buildEvent(
      id: 'noamount', eventDate: base, isOwnAccountTransfer: true,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    final result = await detector.detect(candidate: candidate, id: 'r5');

    expect(result, isNotNull);
    expect(result!.relationshipType, EventRelationshipType.unknownRelationship);
    expect(result.needsReview, isTrue);
  });

  test('only pairs with another own-account-transfer-flagged event, never an ordinary one', () async {
    final candidate = buildEvent(
      id: 'debit3', eventDate: base, amount: 7000,
      direction: SmsTransactionDirection.debit, isOwnAccountTransfer: true,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
    );
    repository.addEvent(buildEvent(
      id: 'ordinary-credit', eventDate: base.add(const Duration(minutes: 1)),
      amount: 7000, direction: SmsTransactionDirection.credit,
      moneyMovement: true, transactionStatus: TransactionStatus.success,
      // isOwnAccountTransfer left false — an ordinary, unrelated credit.
    ));

    final result = await detector.detect(candidate: candidate, id: 'r6');

    expect(result, isNotNull);
    expect(result!.relationshipType, EventRelationshipType.unknownRelationship);
    expect(result.targetEventId, isNull);
  });
}
