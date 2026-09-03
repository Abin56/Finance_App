import 'package:finance_app/features/sms_inbox/domain/financial_event/credit_card_semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('purchase — a charge to the card', () {
    const bodies = [
      'Your credit card ending 4821 was charged Rs.2,500 at a merchant.',
      'Rs.1,500 spent on your credit card ending 1234 at AMAZON.',
      'Your credit card was used for a purchase of Rs.999.',
    ];
    for (final body in bodies) {
      test(
        '"$body"',
        () => expect(
          CreditCardSemantics.detect(body),
          CreditCardSemanticVerdict.purchase,
        ),
      );
    }
  });

  group('bill payment — money paid toward the card balance', () {
    const bodies = [
      'Rs.5,000 payment received towards your credit card ending 1234.',
      'Payment of Rs.5,000 towards your credit card was successful.',
      'Your credit card bill payment of Rs.12,500 has been received.',
      'Credit card payment of Rs.5,000 received. Thank you.',
    ];
    for (final body in bodies) {
      test(
        '"$body"',
        () => expect(
          CreditCardSemantics.detect(body),
          CreditCardSemanticVerdict.billPayment,
        ),
      );
    }
  });

  group(
    'ambiguous — mentions credit card but neither pattern confidently matches',
    () {
      const bodies = [
        'Your credit card statement is ready to view.',
        'Update regarding your credit card ending 1234.',
      ];
      for (final body in bodies) {
        test(
          '"$body"',
          () => expect(
            CreditCardSemantics.detect(body),
            CreditCardSemanticVerdict.ambiguous,
          ),
        );
      }
    },
  );

  test('a message with no credit-card wording at all is notApplicable', () {
    expect(
      CreditCardSemantics.detect('Rs.500 debited from a/c XX1234 to Swiggy.'),
      CreditCardSemanticVerdict.notApplicable,
    );
  });

  test('a debit card message is never mistaken for a credit card one', () {
    expect(
      CreditCardSemantics.detect(
        'Rs.500 spent using your debit card ending 1234.',
      ),
      CreditCardSemanticVerdict.notApplicable,
    );
  });
}
