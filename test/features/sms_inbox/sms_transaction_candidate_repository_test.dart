import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/data/sms_transaction_candidate_repository.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_candidate_cloud.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SmsTransactionCandidateRepository repository;

  SmsTransactionCandidateCloud candidate(String id, {String? accountId}) {
    return SmsTransactionCandidateCloud(
      smsItemId: id,
      amount: 100,
      direction: SmsTransactionDirection.debit,
      eventType: SmsTransactionCategory.upiPayment,
      transactionDate: DateTime(2026, 7, 15),
      confidenceLevel: ConfidenceLevel.high,
      confidenceScore: 0.9,
      needsReview: false,
      createdAt: DateTime(2026, 7, 15),
      accountId: accountId,
    );
  }

  setUp(() {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('smsTransactionCandidates').withConverter<SmsTransactionCandidateCloud>(
          fromFirestore: SmsTransactionCandidateCloud.fromFirestore,
          toFirestore: (c, _) => c.toFirestore(),
        );
    repository = SmsTransactionCandidateRepository(collection);
  });

  test('add stores the document under its deterministic id', () async {
    final c = candidate('sms-1', accountId: 'acc-1');
    await repository.add(c.id, c);

    final stored = await repository.getByKey('sms-1');
    expect(stored?.accountId, 'acc-1');
  });

  test('add again for the same id overwrites rather than duplicating', () async {
    await repository.add('sms-1', candidate('sms-1', accountId: 'acc-1'));
    await repository.add('sms-1', candidate('sms-1', accountId: 'acc-2'));

    final all = await repository.getAll();
    expect(all, hasLength(1));
    expect(all.single.accountId, 'acc-2');
  });

  test('getAll returns every stored candidate', () async {
    await repository.add('sms-1', candidate('sms-1'));
    await repository.add('sms-2', candidate('sms-2'));

    expect(await repository.getAll(), hasLength(2));
  });

  test('deleteById removes exactly one document', () async {
    await repository.add('sms-1', candidate('sms-1'));
    await repository.add('sms-2', candidate('sms-2'));

    await repository.deleteById('sms-1');

    final all = await repository.getAll();
    expect(all.map((c) => c.id), ['sms-2']);
  });

  test('deleteById on a nonexistent id is a harmless no-op', () async {
    await expectLater(repository.deleteById('does-not-exist'), completes);
  });
}
