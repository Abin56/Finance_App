import 'package:finance_app/features/sms_inbox/domain/financial_event/sms_body_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('masks a long account number to its last 4 digits', () {
    final result = SmsBodyRedactor.redact(
      'Your A/c 123456789012 has been debited.',
    );
    expect(result, contains('9012'));
    expect(result, isNot(contains('123456789012')));
  });

  test('masks a phone number embedded in support/promo text', () {
    final result = SmsBodyRedactor.redact(
      'For help call 9876543210 or visit our branch.',
    );
    expect(result, isNot(contains('9876543210')));
    expect(result, contains('3210'));
  });

  test('leaves a bare masked-account 4-digit fragment untouched', () {
    final result = SmsBodyRedactor.redact('A/c XX1234 debited Rs.500.');
    expect(result, contains('XX1234'));
  });

  group('REGRESSION: currency amounts must survive redaction', () {
    test('a comma-grouped amount is untouched (already safe on its own)', () {
      final result = SmsBodyRedactor.redact(
        'Rs.45,230.00 debited from a/c XX1234.',
      );
      expect(result, contains('45,230.00'));
    });

    test(
      'an UNFORMATTED 5-digit amount with a currency symbol is preserved, not masked to "0000"',
      () {
        // This is the bug this class exists to prevent: "Rs 50000" has no
        // comma grouping, so its digits look exactly like an account number
        // to a naive 5+-digit-run masker.
        final result = SmsBodyRedactor.redact(
          'Rs 50000 debited from your account towards EMI.',
        );
        expect(
          result,
          contains('50000'),
          reason:
              'the actual transacted amount must never be destroyed by redaction',
        );
      },
    );

    test('an unformatted 6-digit INR amount is preserved', () {
      final result = SmsBodyRedactor.redact(
        'INR 123456 credited to your account.',
      );
      expect(result, contains('123456'));
    });

    test('SBI-style symbol-less "debited by N" amount is preserved', () {
      final result = SmsBodyRedactor.redact(
        'Your account debited by 20000 on 15-07-26.',
      );
      expect(result, contains('20000'));
    });

    test('a rupee-symbol amount is preserved', () {
      final result = SmsBodyRedactor.redact('₹75000 credited to your account.');
      expect(result, contains('75000'));
    });

    test(
      'an unformatted amount AND a separate real account number in the same message: only the account number is masked',
      () {
        final result = SmsBodyRedactor.redact(
          'Rs 50000 debited from A/c 123456789012 towards EMI.',
        );
        expect(result, contains('50000'), reason: 'amount preserved');
        expect(
          result,
          isNot(contains('123456789012')),
          reason: 'account number still masked',
        );
        expect(result, contains('9012'));
      },
    );
  });

  test('a message with no long digit runs at all is returned unchanged', () {
    const body = 'Rs.500 debited from a/c XX1234 to Swiggy on 15-07-26.';
    expect(SmsBodyRedactor.redact(body), body);
  });
}
