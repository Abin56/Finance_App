import 'package:finance_app/features/sms_inbox/domain/financial_event/reminder_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = ReminderDetector();

  group('positive — reads as a reminder, not a completed transaction', () {
    const reminderBodies = [
      'Your EMI of Rs.8,500 is due tomorrow. Kindly pay to avoid late fee.',
      'Reminder: Your credit card payment of Rs.12,500 is due on 5th Sep.',
      'Your electricity bill of Rs.2,340 is due. Please pay before the due date.',
      'Rs.8,500 will be debited towards your EMI on 20-Sep-2026.',
      'This is a reminder that your loan installment payment is due tomorrow.',
      'Your credit card bill payment of Rs.5,000 is scheduled to be auto-debited on 3rd Sep. Avoid late payment charges.',
      'Upcoming EMI of Rs.3,200 will be deducted from your account on 1st Sep.',
    ];

    for (final body in reminderBodies) {
      test('"$body"', () {
        final verdict = detector.detect(body);
        expect(verdict.isReminder, isTrue, reason: body);
        expect(verdict.reason, isNotNull);
      });
    }
  });

  group(
    'negative — a completed transaction, even with due/bill-shaped wording',
    () {
      const transactionBodies = [
        'Rs.8,500 debited towards your EMI on 15-Jul-2026.',
        'Your EMI of Rs.8,500 was due yesterday and has now been paid successfully.',
        'Payment of Rs.12,500 towards your credit card bill was successful.',
        'Rs.500 debited from a/c XX1234 for UPI payment to Swiggy.',
        'Your electricity bill payment of Rs.2,340 has been processed successfully.',
      ];

      for (final body in transactionBodies) {
        test('"$body"', () {
          expect(detector.detect(body).isReminder, isFalse, reason: body);
        });
      }
    },
  );

  test(
    'a plain debit alert with no due/reminder language at all is never flagged',
    () {
      expect(
        detector
            .detect('Rs.500.00 debited from a/c XX1234 on 15-07-26.')
            .isReminder,
        isFalse,
      );
    },
  );
}
