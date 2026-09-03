import 'package:finance_app/features/sms_inbox/domain/financial_event/reminder_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for Bug 2 — a completion phrase ("was paid", "has
/// been debited", ...) must only override reminder detection for the
/// sentence it actually appears in, not the whole message. A genuinely
/// completed payment must never become a reminder just because
/// reminder-shaped wording appears elsewhere, and a genuine upcoming
/// obligation must never be suppressed just because the same message also
/// mentions a historical/completed payment in a different sentence.
void main() {
  const detector = ReminderDetector();

  test('1. pure completed payment must be completed, not reminder', () {
    final v = detector.detect(
      'Rs.1200 was debited from a/c XX1234 towards electricity bill.',
    );
    expect(v.isReminder, isFalse);
  });

  test('2. pure upcoming reminder must be reminder', () {
    final v = detector.detect(
      'Your electricity bill of Rs.1200 is due on 10 Sep. Kindly pay to avoid late fee.',
    );
    expect(v.isReminder, isTrue);
  });

  test('3. pure due-date reminder must be reminder', () {
    final v = detector.detect('Payment due date for your credit card is 12 Sep.');
    expect(v.isReminder, isTrue);
  });

  test(
    '4. completed payment + future due date in same message must detect the reminder aspect',
    () {
      final v = detector.detect(
        'Your electricity bill of Rs.1200 was paid last month. Your next payment is due on 10 Sep.',
      );
      expect(v.isReminder, isTrue);
    },
  );

  test('5. completed payment + "next payment" phrase must detect the reminder aspect', () {
    final v = detector.detect(
      'Your EMI of Rs.5000 was paid successfully. Your next EMI is due on 5th Oct.',
    );
    expect(v.isReminder, isTrue);
  });

  test(
    '6. completed payment + subscription renewal mention must detect the reminder aspect',
    () {
      final v = detector.detect(
        'Your Netflix subscription of Rs.499 was debited last month. Your subscription will renew tomorrow.',
      );
      expect(v.isReminder, isTrue);
    },
  );

  test('7. failed payment + future due date must be reminder, not completed', () {
    final v = detector.detect(
      'Your EMI payment attempt failed. Please pay before 15 Sep to avoid late fee.',
    );
    expect(v.isReminder, isTrue);
  });

  test(
    '8. successful payment + unrelated historical sentence must remain completed',
    () {
      final v = detector.detect(
        'Rs.500 was debited towards Swiggy order. Thank you for being a loyal customer since last year.',
      );
      expect(v.isReminder, isFalse);
    },
  );

  test(
    '9. reminder containing "paid" referring to a previous payment must remain reminder',
    () {
      final v = detector.detect(
        'Reminder: your last bill of Rs.900 was paid on time. Your new bill of Rs.1100 is due on 10 Sep.',
      );
      expect(v.isReminder, isTrue);
    },
  );

  test('10. adversarial case — completed payment must NOT become a reminder', () {
    final v = detector.detect(
      'Your loan installment of Rs.3200 has been debited successfully. Thank you for your continued EMI payments and upcoming subscription with us.',
    );
    expect(v.isReminder, isFalse);
  });
}
