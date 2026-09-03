import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_builder.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = ObligationBuilder();
  final receivedAt = DateTime(2026, 9, 1, 10);

  group(
    'Safety rule 1: a reminder must never become a completed transaction',
    () {
      test('build() returns null for a completed transaction', () {
        final obligation = builder.build(
          id: 'obl-1',
          sourceEventId: 'sms-1',
          body: 'Rs 500 debited from your account for Swiggy.',
          smsReceivedAt: receivedAt,
          transactionStatus: TransactionStatus.success,
          moneyMovement: true,
        );
        expect(obligation, isNull);
      });

      test('build() returns null for a pending transaction', () {
        final obligation = builder.build(
          id: 'obl-2',
          sourceEventId: 'sms-2',
          body: 'Your UPI payment is pending confirmation.',
          smsReceivedAt: receivedAt,
          transactionStatus: TransactionStatus.pending,
        );
        expect(obligation, isNull);
      });

      test('build() returns null for a failed transaction', () {
        final obligation = builder.build(
          id: 'obl-3',
          sourceEventId: 'sms-3',
          body: 'Your payment has failed. Please retry.',
          smsReceivedAt: receivedAt,
          transactionStatus: TransactionStatus.failed,
        );
        expect(obligation, isNull);
      });

      test('build() returns null for an ambiguous message with no signal', () {
        final obligation = builder.build(
          id: 'obl-4',
          sourceEventId: 'sms-4',
          body: 'Hello there, have a good day.',
          smsReceivedAt: receivedAt,
        );
        expect(obligation, isNull);
      });
    },
  );

  test('build() produces an obligation for a genuine reminder', () {
    final obligation = builder.build(
      id: 'obl-5',
      sourceEventId: 'sms-5',
      body: 'Your EMI of Rs 5,000 will be debited tomorrow.',
      smsReceivedAt: receivedAt,
      amount: const FieldConfidence<double>(
        value: 5000,
        confidence: 0.9,
        source: EvidenceSource.regexOnly,
      ),
      merchant: const FieldConfidence<String>(
        value: 'HDFC Bank',
        confidence: 0.8,
        source: EvidenceSource.regexOnly,
      ),
    );

    expect(obligation, isNotNull);
    expect(obligation!.status, ObligationStatus.upcoming);
    expect(obligation.dueDate.isKnown, isTrue);
    expect(obligation.dueDate.value, DateTime(2026, 9, 2, 10));
    expect(obligation.sourceEventIds, ['sms-5']);
    expect(obligation.title, contains('HDFC Bank'));
    expect(obligation.reviewReasons, isEmpty);
  });

  test('an obligation with an unresolvable date carries a review reason', () {
    final obligation = builder.build(
      id: 'obl-6',
      sourceEventId: 'sms-6',
      body: 'Kindly pay your pending dues at your earliest convenience.',
      smsReceivedAt: receivedAt,
    );

    expect(obligation, isNotNull);
    expect(obligation!.dueDate.isKnown, isFalse);
    expect(obligation.status, ObligationStatus.detected);
    expect(
      obligation.reviewReasons,
      contains('No due/scheduled date could be resolved from the message.'),
    );
  });

  test('an obligation whose due date is already in the past starts as due', () {
    final obligation = builder.build(
      id: 'obl-7',
      sourceEventId: 'sms-7',
      body: 'Your credit card payment is due on 25 Aug.',
      smsReceivedAt: receivedAt,
    );

    expect(obligation, isNotNull);
    expect(obligation!.dueDate.value, DateTime(2026, 8, 25));
    expect(obligation.status, ObligationStatus.due);
  });

  test('smsReceivedAt is never used as the resolved due date itself', () {
    final obligation = builder.build(
      id: 'obl-8',
      sourceEventId: 'sms-8',
      body: 'Your EMI of Rs 5,000 will be debited on 5 Sep.',
      smsReceivedAt: receivedAt,
    );

    expect(obligation, isNotNull);
    expect(
      obligation!.dueDate.value,
      isNot(receivedAt),
      reason:
          'The scheduled debit date (5 Sep) must win over the SMS receipt date (1 Sep).',
    );
    expect(obligation.dueDate.value, DateTime(2026, 9, 5));
  });

  test(
    'classification is deterministic across repeated builds of the same message',
    () {
      const body = 'Your electricity bill of Rs 1,200 is due on 7 Sep.';
      final first = builder.build(
        id: 'obl-9a',
        sourceEventId: 'sms-9a',
        body: body,
        smsReceivedAt: receivedAt,
      );
      final second = builder.build(
        id: 'obl-9b',
        sourceEventId: 'sms-9b',
        body: body,
        smsReceivedAt: receivedAt,
      );
      expect(first!.obligationType, second!.obligationType);
      expect(first.status, second.status);
      expect(first.dueDate.value, second.dueDate.value);
    },
  );
}
