import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/vpa_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('explicit phrasing — always trusted, marked isExplicit', () {
    test('"paid ₹800 using PhonePe"', () {
      final result = PaymentProviderResolver.resolve(
        body: 'Paid Rs.800 using PhonePe to swiggy@icici.',
      );
      expect(result?.provider, PaymentProvider.phonePe);
      expect(result?.isExplicit, isTrue);
    });

    test('"via Google Pay"', () {
      final result = PaymentProviderResolver.resolve(
        body: 'Rs.500 sent via Google Pay to a friend.',
      );
      expect(result?.provider, PaymentProvider.googlePay);
      expect(result?.isExplicit, isTrue);
    });

    test('"via GPay" (short form)', () {
      final result = PaymentProviderResolver.resolve(
        body: 'Rs.500 sent via GPay.',
      );
      expect(result?.provider, PaymentProvider.googlePay);
    });

    test('"using Paytm"', () {
      final result = PaymentProviderResolver.resolve(
        body: 'Rs.500 paid using Paytm.',
      );
      expect(result?.provider, PaymentProvider.paytm);
    });

    test('"through Amazon Pay"', () {
      final result = PaymentProviderResolver.resolve(
        body: 'Rs.500 paid through Amazon Pay.',
      );
      expect(result?.provider, PaymentProvider.amazonPay);
    });
  });

  group(
    'handle-based hint — only when no explicit phrasing exists, marked NOT isExplicit',
    () {
      test('a @ybl VPA hints at PhonePe', () {
        final vpa = VpaParser.parse('someone@ybl');
        final result = PaymentProviderResolver.resolve(
          body: 'Rs.500 sent to someone@ybl.',
          vpa: vpa,
        );
        expect(result?.provider, PaymentProvider.phonePe);
        expect(result?.isExplicit, isFalse);
      });

      test('a @oksbi VPA hints at Google Pay', () {
        final vpa = VpaParser.parse('someone@oksbi');
        final result = PaymentProviderResolver.resolve(
          body: 'Rs.500 sent to someone@oksbi.',
          vpa: vpa,
        );
        expect(result?.provider, PaymentProvider.googlePay);
        expect(result?.isExplicit, isFalse);
      });
    },
  );

  test('explicit phrasing always wins over a conflicting handle hint', () {
    final vpa = VpaParser.parse('someone@oksbi');
    final result = PaymentProviderResolver.resolve(
      body: 'Paid Rs.500 using PhonePe to someone@oksbi.',
      vpa: vpa,
    );
    expect(result?.provider, PaymentProvider.phonePe);
    expect(result?.isExplicit, isTrue);
  });

  test('no signal at all (plain bank SMS) resolves to null, never a guess', () {
    final result = PaymentProviderResolver.resolve(
      body: 'Rs.500 debited from a/c XX1234.',
    );
    expect(result, isNull);
  });

  test('an unrecognized VPA handle resolves to null', () {
    final vpa = VpaParser.parse('someone@somebank');
    final result = PaymentProviderResolver.resolve(
      body: 'Rs.500 sent to someone@somebank.',
      vpa: vpa,
    );
    expect(result, isNull);
  });
}
