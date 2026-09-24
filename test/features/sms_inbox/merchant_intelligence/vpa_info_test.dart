import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/upi_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/vpa_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VpaParser.parse', () {
    test('splits a business VPA into local part and handle', () {
      final vpa = VpaParser.parse('swiggy@upi');
      expect(vpa, isNotNull);
      expect(vpa!.localPart, 'swiggy');
      expect(vpa.handle, 'upi');
      expect(vpa.localPartIsPhoneNumber, isFalse);
    });

    test('flags a phone-number local part without ever naming a person', () {
      final vpa = VpaParser.parse('9876543210@oksbi');
      expect(vpa, isNotNull);
      expect(vpa!.localPart, '9876543210');
      expect(vpa.localPartIsPhoneNumber, isTrue);
      expect(vpa.handle, 'oksbi');
    });

    test('recognizes a +91-prefixed phone number local part', () {
      final vpa = VpaParser.parse('+919876543210@ybl');
      expect(vpa, isNotNull);
      expect(vpa!.localPartIsPhoneNumber, isTrue);
    });

    test('resolves known bank/app handles to a UpiProvider', () {
      expect(VpaParser.parse('swiggy@ybl')!.provider, UpiProvider.phonePe);
      expect(VpaParser.parse('shop@oksbi')!.provider, UpiProvider.bankUpi);
      expect(VpaParser.parse('shop@paytm')!.provider, UpiProvider.paytm);
    });

    test('an unrecognized handle resolves to unknown, never guessed', () {
      final vpa = VpaParser.parse('shop@somebank');
      expect(vpa!.provider, UpiProvider.unknown);
    });

    test('returns null for non-VPA-shaped text', () {
      expect(VpaParser.parse('ABC Bakery'), isNull);
      expect(VpaParser.parse(null), isNull);
      expect(VpaParser.parse(''), isNull);
    });
  });

  group('VpaParser.findFirstInText', () {
    test('finds a VPA embedded in a full SMS body', () {
      final vpa = VpaParser.findFirstInText(
        'Rs.350 sent to 9876543210@oksbi via UPI from A/c XX5678.',
      );
      expect(vpa, isNotNull);
      expect(vpa!.raw, '9876543210@oksbi');
    });

    test('returns null when no VPA is present', () {
      expect(
        VpaParser.findFirstInText(
          'Rs.500 debited from a/c XX1234 on 15-07-26.',
        ),
        isNull,
      );
    });
  });

  group('UpiProviderResolver.fromMentionInText', () {
    test('detects an explicit app mention regardless of a VPA handle', () {
      expect(
        UpiProviderResolver.fromMentionInText(
          'Payment of Rs.240 to Zomato via PhonePe was successful.',
        ),
        UpiProvider.phonePe,
      );
      expect(
        UpiProviderResolver.fromMentionInText(
          'You paid Rs.120 to Rohit Kumar using Google Pay.',
        ),
        UpiProvider.googlePay,
      );
      expect(
        UpiProviderResolver.fromMentionInText('Paid using GPay to the vendor.'),
        UpiProvider.googlePay,
      );
    });

    test('returns unknown when no provider is mentioned', () {
      expect(
        UpiProviderResolver.fromMentionInText(
          'Rs.500 debited from a/c XX1234.',
        ),
        UpiProvider.unknown,
      );
    });
  });
}
