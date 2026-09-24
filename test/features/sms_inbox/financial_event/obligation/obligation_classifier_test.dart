import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_classifier.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_semantic_bucket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classifier = ObligationClassifier();

  group('safety invariants (Part 7 of the task)', () {
    test('moneyMovement == true is always safe to treat as completed', () {
      final result = classifier.classify(
        body: 'Your EMI of Rs 5,000 will be debited tomorrow.',
        moneyMovement: true,
        transactionStatus: TransactionStatus.success,
      );
      expect(result.isSafeToTreatAsCompletedTransaction, isTrue);
      expect(result.bucket, ObligationSemanticBucket.completed);
    });

    test(
      'reminder-shaped text with moneyMovement left null never resolves to completed',
      () {
        final reminders = [
          'Your EMI of Rs 5,000 will be debited tomorrow.',
          'Your credit card payment of Rs 10,000 is due on 5 Sep.',
          'Please pay Rs 2,000 before 10 Sep.',
          'Your standing instruction is scheduled for tomorrow.',
          'Your loan EMI is due.',
          'Payment reminder: Rs 500 is pending.',
        ];
        for (final body in reminders) {
          final result = classifier.classify(body: body);
          expect(
            result.bucket,
            isNot(ObligationSemanticBucket.completed),
            reason: 'body: "$body"',
          );
          expect(
            result.isSafeToTreatAsCompletedTransaction,
            isFalse,
            reason: 'body: "$body"',
          );
        }
      },
    );

    test(
      'a failed transactionStatus never resolves to completed or reminder',
      () {
        final result = classifier.classify(
          body: 'Your EMI auto-debit attempt failed.',
          transactionStatus: TransactionStatus.failed,
        );
        expect(result.bucket, ObligationSemanticBucket.failed);
        expect(result.bucket.isOutstanding, isFalse);
      },
    );

    test('a pending transactionStatus never resolves to completed', () {
      final result = classifier.classify(
        body: 'Your payment is pending confirmation.',
        transactionStatus: TransactionStatus.pending,
      );
      expect(result.bucket, ObligationSemanticBucket.pending);
      expect(result.isSafeToTreatAsCompletedTransaction, isFalse);
    });

    test(
      'a reversed transactionStatus never becomes a fresh obligation or expense',
      () {
        final result = classifier.classify(
          body: 'Your payment was reversed and credited back.',
          transactionStatus: TransactionStatus.reversed,
        );
        expect(result.bucket, ObligationSemanticBucket.reversed);
        expect(result.bucket.isOutstanding, isFalse);
      },
    );

    test(
      'a refunded transactionStatus never becomes income or an obligation',
      () {
        final result = classifier.classify(
          body: 'Refund of Rs 500 credited to your account.',
          transactionStatus: TransactionStatus.refunded,
        );
        expect(result.bucket, ObligationSemanticBucket.refund);
        expect(result.bucket.isOutstanding, isFalse);
      },
    );

    test(
      'no signal at all resolves to unknown, never guessed as completed',
      () {
        final result = classifier.classify(
          body: 'Hello, this is a test message.',
        );
        expect(result.bucket, ObligationSemanticBucket.unknown);
        expect(result.confidence, 0.0);
      },
    );
  });

  group('obligation subtype classification', () {
    test('EMI keyword wins even when "loan" also appears', () {
      final result = classifier.classify(
        body: 'Reminder: Your loan EMI payment is pending.',
      );
      expect(result.obligationType.name, 'emiObligation');
    });

    test('subscription keyword is detected from a known provider name', () {
      final result = classifier.classify(
        body: 'Your Netflix subscription will be charged tomorrow.',
      );
      expect(result.obligationType.name, 'subscriptionRenewal');
    });

    test(
      'a reminder with no specific keyword falls back to a generic type',
      () {
        final result = classifier.classify(
          body: 'Kindly pay the pending amount at your earliest convenience.',
        );
        expect(result.obligationType.name, 'paymentReminder');
      },
    );
  });

  group('bucket refinement (due vs upcoming vs reminder)', () {
    test('an explicit due-date phrase resolves to due', () {
      final result = classifier.classify(body: 'Your bill is due on 5 Sep.');
      expect(result.bucket, ObligationSemanticBucket.due);
    });

    test('a future-tense scheduled-debit phrase resolves to upcoming', () {
      final result = classifier.classify(
        body: 'Your account will be auto-debited on 5 Sep.',
      );
      expect(result.bucket, ObligationSemanticBucket.upcoming);
    });

    test('a generic reminder phrase with neither resolves to reminder', () {
      final result = classifier.classify(body: 'Kindly pay your pending dues.');
      expect(result.bucket, ObligationSemanticBucket.reminder);
    });
  });
}
