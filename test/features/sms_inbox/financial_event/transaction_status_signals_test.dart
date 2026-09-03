import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('failed', () {
    const bodies = [
      'Your UPI payment of Rs.500 has failed due to insufficient balance.',
      'Transaction declined. Your card payment of Rs.1,200 could not be processed.',
      'Your payment of Rs.500 was unsuccessful. Please try again.',
    ];
    for (final body in bodies) {
      test(
        '"$body"',
        () => expect(
          TransactionStatusSignals.detect(body),
          TransactionStatus.failed,
        ),
      );
    }
  });

  group('pending', () {
    const bodies = [
      'Your payment of Rs.500 is pending confirmation from the bank.',
      'Your transaction is currently processing. We will notify you once complete.',
      'Your refund request is under process.',
    ];
    for (final body in bodies) {
      test(
        '"$body"',
        () => expect(
          TransactionStatusSignals.detect(body),
          TransactionStatus.pending,
        ),
      );
    }
  });

  group('reversed', () {
    test('"Rs.5,000 debited on 10-Jul has been reversed to your account."', () {
      expect(
        TransactionStatusSignals.detect(
          'Rs.5,000 debited on 10-Jul has been reversed to your account.',
        ),
        TransactionStatus.reversed,
      );
    });
  });

  group('refunded', () {
    test('"Rs.500 refunded to your account by Swiggy."', () {
      expect(
        TransactionStatusSignals.detect(
          'Rs.500 refunded to your account by Swiggy.',
        ),
        TransactionStatus.refunded,
      );
    });
  });

  group('success — explicit wording ("known", not inferred)', () {
    const bodies = [
      'Your UPI payment of Rs.500 was successful.',
      'Rs.500 has been debited from your account.',
      'Payment of Rs.1,200 successfully processed.',
    ];
    for (final body in bodies) {
      test('"$body"', () {
        final result = TransactionStatusSignals.detectDetailed(body);
        expect(result.status, TransactionStatus.success);
        expect(
          result.isInferred,
          isFalse,
          reason:
              'explicit "successful"/"has been X" wording is known, not inferred',
        );
      });
      test('"$body" (detect() convenience wrapper agrees)', () {
        expect(
          TransactionStatusSignals.detect(body),
          TransactionStatus.success,
        );
      });
    }
  });

  group(
    'success — inferred from a bare completion verb, no explicit "successful"/"has been" framing',
    () {
      const bodies = [
        'Rs.500 debited from a/c XX1234 to Swiggy.',
        'Rs.499 paid to merchant@ybl via UPI.',
        'Rs.500 sent to abc@upi.',
      ];
      for (final body in bodies) {
        test('"$body"', () {
          final result = TransactionStatusSignals.detectDetailed(body);
          expect(result.status, TransactionStatus.success);
          expect(
            result.isInferred,
            isTrue,
            reason:
                'a bare completion verb with no "successful"/"has been" framing is inferred, not known',
          );
        });
      }
    },
  );

  test(
    'a message with no completion verb and no status wording at all resolves to unknown, not a guess',
    () {
      final result = TransactionStatusSignals.detectDetailed(
        'Your Available Balance is Rs.45,230.00 as of 15-07-26.',
      );
      expect(result.status, TransactionStatus.unknown);
      expect(result.isInferred, isFalse);
    },
  );

  test(
    'a failed status wins over a coincidental "successful" elsewhere in a longer message',
    () {
      // Failed is checked first — most specific/actionable status wins when a
      // message mixes wording (e.g. quoting what a successful payment usually
      // looks like while explaining this one failed).
      expect(
        TransactionStatusSignals.detect(
          'Your payment has failed. Normally a successful payment completes within seconds.',
        ),
        TransactionStatus.failed,
      );
    },
  );
}
