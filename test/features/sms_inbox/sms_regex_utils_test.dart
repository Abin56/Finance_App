import 'package:finance_app/features/sms_inbox/domain/sms_regex_utils.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractDirection', () {
    test('a reversal/refund crediting a Debit Card is a credit, not a debit', () {
      // Regression: the bare noun "Debit Card" used to satisfy the debit
      // keyword list, and since it appears before "credited" in this
      // wording, the position-based tie-break picked debit — wrong sign on
      // a real credit.
      const body =
          'Rs.500.00 reversed and credited back to your HDFC Bank Debit Card XX1234 account.';
      expect(
        SmsRegexUtils.extractDirection(body),
        SmsTransactionDirection.credit,
      );
    });

    test('still detects a genuine debit via "debited"', () {
      const body = 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26.';
      expect(
        SmsRegexUtils.extractDirection(body),
        SmsTransactionDirection.debit,
      );
    });

    test('still detects a genuine debit via "spent"', () {
      const body = 'Rs.899.99 spent on card XX2222 at STORE.';
      expect(
        SmsRegexUtils.extractDirection(body),
        SmsTransactionDirection.debit,
      );
    });
  });

  group('extractMerchant', () {
    test('does not mistake a customer-care email for the merchant', () {
      // Regression: the VPA/email pattern used to win unconditionally, so a
      // bank's own disclaimer email became the "merchant".
      const body =
          'Rs.500.00 debited from a/c XX1234. For help, mail us at customercare@hdfcbank.com';
      expect(
        SmsRegexUtils.extractMerchant(body),
        isNot('customercare@hdfcbank'),
      );
    });

    test('still extracts a genuine UPI VPA merchant', () {
      const body =
          'Rs.499.00 paid to merchant@ybl via UPI on 15-07-26. UPI Ref No 987654321098.';
      expect(SmsRegexUtils.extractMerchant(body), 'merchant@ybl');
    });

    test(
      'falls back to the merchant-name pattern when there is no UPI/VPA context',
      () {
        const body =
            'Rs.500.00 debited from a/c XX1234. For help, mail us at customercare@hdfcbank.com';
        // No "trf to/to/at NAME" phrasing either, so this is expected to find
        // nothing — the point is it must not be the email.
        expect(SmsRegexUtils.extractMerchant(body), isNull);
      },
    );
  });

  group('guessCategory', () {
    test('a salary credit arriving via UPI is salaryCredit, not upiReceive', () {
      // Regression: the UPI check used to run before the specific-reason
      // checks, so a salary/refund credit that also mentions UPI would be
      // miscategorized as the generic upiReceive.
      const body =
          'Rs.50,000.00 credited to a/c XX1234 via UPI. Info: salary for July.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.credit),
        SmsTransactionCategory.salaryCredit,
      );
    });

    test('a refund arriving via UPI is refund, not upiReceive', () {
      const body =
          'Rs.250.00 credited to a/c XX1234 via UPI. Refund for order #123.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.credit),
        SmsTransactionCategory.refund,
      );
    });

    test('a plain UPI payment with no specific reason is still upiPayment', () {
      const body = 'Rs.499.00 paid to merchant@ybl via UPI on 15-07-26.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.debit),
        SmsTransactionCategory.upiPayment,
      );
    });

    test('a cashback credit is cashback, not a generic bank credit', () {
      const body =
          'Rs.25.00 cashback credited to your account for your recent purchase.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.credit),
        SmsTransactionCategory.cashback,
      );
    });

    test('an interest credit is interestCredit', () {
      const body =
          'Interest of Rs.145.32 credited to your savings account for Q2.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.credit),
        SmsTransactionCategory.interestCredit,
      );
    });

    test('an annual fee charge is bankFee', () {
      const body = 'Rs.500 annual fee has been debited from your credit card.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.debit),
        SmsTransactionCategory.bankFee,
      );
    });

    test('a late payment charge is bankFee', () {
      const body =
          'Rs.100 late payment charge levied on your credit card account.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.debit),
        SmsTransactionCategory.bankFee,
      );
    });

    test('a mobile recharge debit is recharge', () {
      const body = 'Rs.199 debited for mobile recharge on 15-07-26.';
      expect(
        SmsRegexUtils.guessCategory(body, SmsTransactionDirection.debit),
        SmsTransactionCategory.recharge,
      );
    });
  });

  group('extractAmount — multiple amounts in one message', () {
    test('prefers the debited amount over a balance figure stated before it', () {
      const body =
          'Avl Bal Rs.45,230.00. Rs.500.00 debited from a/c XX1234 on 15-07-26.';
      expect(SmsRegexUtils.extractAmount(body), 500.0);
    });

    test(
      'prefers the debited amount over a balance figure stated after it',
      () {
        const body = 'Rs.500.00 debited from a/c XX1234. Avl Bal Rs.45,230.00.';
        expect(SmsRegexUtils.extractAmount(body), 500.0);
      },
    );

    test(
      'falls back to the only amount present even if it is balance-adjacent',
      () {
        const body = 'Your Available Balance is Rs.45,230.00 as of 15-07-26.';
        expect(SmsRegexUtils.extractAmount(body), 45230.0);
      },
    );

    test(
      'a single-amount message is completely unaffected by the balance-skip logic',
      () {
        const body = 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26.';
        expect(SmsRegexUtils.extractAmount(body), 1250.0);
      },
    );
  });

  group('extractMaskedAccount', () {
    const boiSms =
        'Rs.350.00 debited A/cXX9585 and credited to ABIN  JOHN via UPI Ref No 630557620611 on 01Nov26. Call 18001031906, if not done by you. -BOI';

    test('BOI SMS with glued "A/cXX9585" yields 9585', () {
      expect(SmsRegexUtils.extractMaskedAccount(boiSms), '9585');
    });

    const variants = <String, String>{
      'A/cXX9585': '9585',
      'A/c XX9585': '9585',
      'A/c no. XXXX9585': '9585',
      'A/c No: XX9585': '9585',
      'a/c *9585': '9585',
      'Ac XX9585': '9585',
      'AC XXXXXX9585': '9585',
      'acct XX9585': '9585',
      'account ending 9585': '9585',
      'a/c ending with 9585': '9585',
      'A/c ••••9585': '9585',
      'A/c x*X•9585': '9585',
      'card ending 1234': '1234',
      'Card xx1234': '1234',
      'card XXXX1234': '1234',
    };
    variants.forEach((fragment, expected) {
      test('"$fragment" -> $expected', () {
        expect(
          SmsRegexUtils.extractMaskedAccount('Rs.10 debited from $fragment.'),
          expected,
        );
      });
    });

    test('helpline number and Ref No alone give null', () {
      const body =
          'Txn done via UPI Ref No 630557620611. Call 18001031906 if not done by you.';
      expect(SmsRegexUtils.extractMaskedAccount(body), isNull);
    });

    test('no account number gives null', () {
      expect(
        SmsRegexUtils.extractMaskedAccount('Rs.350.00 debited on 01Nov26.'),
        isNull,
      );
    });

    test('never takes a longer number after the keyword as a last-4', () {
      expect(
        SmsRegexUtils.extractMaskedAccount('A/c 18001031906 debited'),
        isNull,
      );
    });
  });
}
