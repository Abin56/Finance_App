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
      const body = 'Rs.500.00 reversed and credited back to your HDFC Bank Debit Card XX1234 account.';
      expect(SmsRegexUtils.extractDirection(body), SmsTransactionDirection.credit);
    });

    test('still detects a genuine debit via "debited"', () {
      const body = 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26.';
      expect(SmsRegexUtils.extractDirection(body), SmsTransactionDirection.debit);
    });

    test('still detects a genuine debit via "spent"', () {
      const body = 'Rs.899.99 spent on card XX2222 at STORE.';
      expect(SmsRegexUtils.extractDirection(body), SmsTransactionDirection.debit);
    });
  });

  group('extractMerchant', () {
    test('does not mistake a customer-care email for the merchant', () {
      // Regression: the VPA/email pattern used to win unconditionally, so a
      // bank's own disclaimer email became the "merchant".
      const body = 'Rs.500.00 debited from a/c XX1234. For help, mail us at customercare@hdfcbank.com';
      expect(SmsRegexUtils.extractMerchant(body), isNot('customercare@hdfcbank'));
    });

    test('still extracts a genuine UPI VPA merchant', () {
      const body = 'Rs.499.00 paid to merchant@ybl via UPI on 15-07-26. UPI Ref No 987654321098.';
      expect(SmsRegexUtils.extractMerchant(body), 'merchant@ybl');
    });

    test('falls back to the merchant-name pattern when there is no UPI/VPA context', () {
      const body = 'Rs.500.00 debited from a/c XX1234. For help, mail us at customercare@hdfcbank.com';
      // No "trf to/to/at NAME" phrasing either, so this is expected to find
      // nothing — the point is it must not be the email.
      expect(SmsRegexUtils.extractMerchant(body), isNull);
    });
  });

  group('guessCategory', () {
    test('a salary credit arriving via UPI is salaryCredit, not upiReceive', () {
      // Regression: the UPI check used to run before the specific-reason
      // checks, so a salary/refund credit that also mentions UPI would be
      // miscategorized as the generic upiReceive.
      const body = 'Rs.50,000.00 credited to a/c XX1234 via UPI. Info: salary for July.';
      expect(SmsRegexUtils.guessCategory(body, SmsTransactionDirection.credit), SmsTransactionCategory.salaryCredit);
    });

    test('a refund arriving via UPI is refund, not upiReceive', () {
      const body = 'Rs.250.00 credited to a/c XX1234 via UPI. Refund for order #123.';
      expect(SmsRegexUtils.guessCategory(body, SmsTransactionDirection.credit), SmsTransactionCategory.refund);
    });

    test('a plain UPI payment with no specific reason is still upiPayment', () {
      const body = 'Rs.499.00 paid to merchant@ybl via UPI on 15-07-26.';
      expect(SmsRegexUtils.guessCategory(body, SmsTransactionDirection.debit), SmsTransactionCategory.upiPayment);
    });
  });
}
