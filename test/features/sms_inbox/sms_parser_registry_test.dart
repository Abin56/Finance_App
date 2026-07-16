import 'package:finance_app/features/sms_inbox/domain/raw_sms_message.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_parser_registry.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registry = SmsParserRegistry();

  RawSmsMessage msg(String address, String body, {DateTime? date}) =>
      RawSmsMessage(address: address, body: body, date: date ?? DateTime(2026, 7, 15, 14, 45));

  group('SmsFinancialFilter.isFinancial', () {
    test('rejects OTP messages', () {
      final m = msg('VM-HDFCBK', '123456 is your OTP for txn of Rs.500. Do not share OTP with anyone.');
      expect(SmsFinancialFilter.isFinancial(m), isFalse);
    });

    test('rejects promotional messages', () {
      final m = msg('AD-OFFERS', 'Flat 50% off on electronics! Shop now, sale is now live.');
      expect(SmsFinancialFilter.isFinancial(m), isFalse);
    });

    test('rejects delivery updates', () {
      final m = msg('VM-DELIVR', 'Your order #12345 has been dispatched and will be delivered tomorrow.');
      expect(SmsFinancialFilter.isFinancial(m), isFalse);
    });

    test('rejects recharge reminders', () {
      final m = msg('VM-AIRTEL', 'Your plan expires soon. Recharge now to continue enjoying uninterrupted service.');
      expect(SmsFinancialFilter.isFinancial(m), isFalse);
    });

    test('accepts a genuine debit alert', () {
      final m = msg('VM-HDFCBK', 'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012.');
      expect(SmsFinancialFilter.isFinancial(m), isTrue);
    });

    test('accepts a genuine credit alert', () {
      final m = msg('VM-ICICIB', 'Rs.50,000.00 credited to a/c XX1234 on 15-07-26. Info: NEFT salary. Avl Bal Rs.75,000.00');
      expect(SmsFinancialFilter.isFinancial(m), isTrue);
    });

    test('accepts a genuine debit whose merchant name happens to contain "Sale Store"', () {
      // Regression: the promotional negative-list pattern for "sale ...
      // shop/buy/store" used to reject this outright, silently dropping a
      // real transaction SMS with no recovery path.
      final m = msg(
        'VM-HDFCBK',
        'Rs.1500.00 spent at Flipkart Big Billion Sale Store on your HDFC Bank Debit Card XX1234.',
      );
      expect(SmsFinancialFilter.isFinancial(m), isTrue);
    });

    test('still rejects a promo that merely quotes an amount with no transaction verb', () {
      final m = msg('AD-OFFERS', 'Get a cashback offer of Rs.500 off your next purchase! Sale is now live.');
      expect(SmsFinancialFilter.isFinancial(m), isFalse);
    });

    test('OTP is rejected even if the message also contains a transaction verb', () {
      final m = msg('VM-HDFCBK', '123456 is your OTP to authorize a payment of Rs.500 debited from a/c XX1234. Do not share OTP.');
      expect(SmsFinancialFilter.isFinancial(m), isFalse);
    });
  });

  group('bank-specific parsing', () {
    test('parses an HDFC UPI debit alert with high confidence', () {
      final m = msg(
        'VM-HDFCBK',
        'Rs.1,250.00 debited from a/c XX5623 on 15-07-26 to VPA swiggy@icici. Ref No 123456789012. Not you? Call 18002586161',
      );
      final result = registry.tryParse(m);

      expect(result, isNotNull);
      expect(result!.amount, 1250.0);
      expect(result.direction, SmsTransactionDirection.debit);
      expect(result.bankName, 'HDFC Bank');
      expect(result.maskedAccountOrCard, '5623');
      expect(result.referenceNumber, '123456789012');
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('parses an ICICI credit alert', () {
      final m = msg(
        'VD-ICICIB',
        'Rs.50,000.00 credited to a/c XX1234 on 15-07-26. Info: NEFT salary. Avl Bal Rs.75,000.00 - ICICI Bank',
      );
      final result = registry.tryParse(m);

      expect(result, isNotNull);
      expect(result!.amount, 50000.0);
      expect(result.direction, SmsTransactionDirection.credit);
      expect(result.bankName, 'ICICI Bank');
      expect(result.category, SmsTransactionCategory.salaryCredit);
    });

    test('parses an SBI ATM withdrawal', () {
      final m = msg('AX-SBIBNK', 'Rs.5,000.00 withdrawn at ATM from a/c XX9876 on 15-07-26. -SBI');
      final result = registry.tryParse(m);

      expect(result, isNotNull);
      expect(result!.bankName, 'State Bank of India');
      expect(result.category, SmsTransactionCategory.atmWithdrawal);
    });

    test('parses an Axis Bank credit card purchase', () {
      final m = msg('JM-AXISBK', 'Rs.2,499.00 spent on your Axis Bank Credit Card ending 4321 at AMAZON on 15-07-26.');
      final result = registry.tryParse(m);

      expect(result, isNotNull);
      expect(result!.bankName, 'Axis Bank');
      expect(result.category, SmsTransactionCategory.creditCardPurchase);
      expect(result.maskedAccountOrCard, '4321');
    });
  });

  group('generic UPI parsing (unrecognized sender)', () {
    test('parses a PhonePe-style UPI payment', () {
      final m = msg('PHONEPE', 'Rs.499.00 paid to merchant@ybl via UPI on 15-07-26. UPI Ref No 987654321098.');
      final result = registry.tryParse(m);

      expect(result, isNotNull);
      expect(result!.amount, 499.0);
      expect(result.direction, SmsTransactionDirection.debit);
      expect(result.category, SmsTransactionCategory.upiPayment);
      expect(result.merchantOrSender, 'merchant@ybl');
      expect(result.bankName, isNull);
    });
  });

  group('generic fallback parsing (unrecognized bank+no UPI keyword)', () {
    test('still extracts amount/direction from an unrecognized-format alert', () {
      final m = msg('BK-UNKNWN', 'INR 750.50 debited from your account for bill payment. Avl bal INR 4,250.00.');
      final result = registry.tryParse(m);

      expect(result, isNotNull);
      expect(result!.amount, 750.50);
      expect(result.direction, SmsTransactionDirection.debit);
      expect(result.confidence, lessThan(0.6));
    });

    test('returns null when no amount can be found at all', () {
      final m = msg('BK-UNKNWN', 'Your account statement is now available for download.');
      final result = registry.tryParse(m);
      expect(result, isNull);
    });
  });

  group('amount formatting edge cases', () {
    test('handles amount without decimal places', () {
      final m = msg('VM-HDFCBK', 'Rs.500 debited from a/c XX1111 towards UPI payment.');
      final result = registry.tryParse(m);
      expect(result!.amount, 500.0);
    });

    test('handles INR prefix instead of Rs', () {
      final m = msg('VM-HDFCBK', 'INR 1,00,000.00 credited to a/c XX1111.');
      final result = registry.tryParse(m);
      expect(result!.amount, 100000.0);
    });

    test('handles rupee symbol prefix', () {
      final m = msg('VM-HDFCBK', '₹899.99 spent on card XX2222 at STORE.');
      final result = registry.tryParse(m);
      expect(result!.amount, 899.99);
    });
  });
}
