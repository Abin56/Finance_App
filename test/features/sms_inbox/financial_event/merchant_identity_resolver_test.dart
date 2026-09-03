import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_identity_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_source.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = MerchantIdentityResolver();

  group('resolveDeterministic', () {
    test('a known VPA local part resolves via the catalog, isKnown true', () {
      final identity = resolver.resolveDeterministic(
        regexMerchantText: 'swiggy@icici',
        body: 'Rs.450 paid to swiggy@icici via UPI.',
      );
      expect(identity.isKnown, isTrue);
      expect(identity.displayName, 'Swiggy');
      expect(identity.source, MerchantSource.vpaCatalog);
      expect(identity.evidence, 'swiggy@icici');
    });

    test(
      'REGRESSION (never invent identity): "₹450 paid to 9876543210@oksbi" must stay unknown, never become a person\'s name',
      () {
        final identity = resolver.resolveDeterministic(
          regexMerchantText: '9876543210@oksbi',
          body: '₹450 paid to 9876543210@oksbi',
        );
        expect(
          identity.isKnown,
          isFalse,
          reason: 'a bare unrecognized VPA is evidence, not identity',
        );
        expect(identity.displayName, isNull);
        expect(
          identity.vpa?.raw,
          '9876543210@oksbi',
          reason: 'the VPA itself is still preserved as evidence',
        );
      },
    );

    test(
      'explicit human-shaped SMS text not in the catalog resolves with a lower-confidence explicitText source',
      () {
        final identity = resolver.resolveDeterministic(
          regexMerchantText: 'ABC Store',
          body: 'Rs.500 paid to ABC Store.',
        );
        expect(identity.isKnown, isTrue);
        expect(identity.source, MerchantSource.explicitText);
        expect(identity.displayName, 'ABC Store');
        expect(
          identity.confidence,
          lessThan(0.8),
          reason: 'weaker than a catalog match',
        );
      },
    );

    test('a bare masked-account-shaped token never becomes an identity', () {
      final identity = resolver.resolveDeterministic(
        regexMerchantText: 'XXXX1234',
        body: 'Rs.500 debited XXXX1234.',
      );
      expect(identity.isKnown, isFalse);
    });

    test('no merchant text at all resolves to unknown', () {
      final identity = resolver.resolveDeterministic(
        regexMerchantText: null,
        body: 'Rs.500 debited from a/c XX1234.',
      );
      expect(identity.isKnown, isFalse);
      expect(identity.vpa, isNull);
    });

    group('payment provider separation (never confused with the merchant)', () {
      test(
        '"Paid ₹800 using PhonePe to swiggy@upi" resolves merchant=Swiggy, provider=PhonePe',
        () {
          final identity = resolver.resolveDeterministic(
            regexMerchantText: 'swiggy@upi',
            body: 'Paid Rs.800 using PhonePe to swiggy@upi.',
          );
          expect(identity.displayName, 'Swiggy');
          expect(identity.paymentProvider, PaymentProvider.phonePe);
        },
      );

      test('the provider is never mistaken for the merchant name', () {
        final identity = resolver.resolveDeterministic(
          regexMerchantText: 'swiggy@upi',
          body: 'Paid Rs.800 using PhonePe to swiggy@upi.',
        );
        expect(identity.displayName, isNot('PhonePe'));
      });
    });

    group('merchant normalization — conservative, never over-merging', () {
      test(
        'SWIGGY, Swiggy, SWIGGY INDIA, and swiggy@upi all resolve to the same canonical "Swiggy"',
        () {
          for (final text in ['SWIGGY', 'Swiggy', 'SWIGGY INDIA']) {
            final identity = resolver.resolveDeterministic(
              regexMerchantText: text,
              body: 'Rs.500 paid to $text.',
            );
            expect(identity.displayName, 'Swiggy', reason: 'text: $text');
          }
          final vpaIdentity = resolver.resolveDeterministic(
            regexMerchantText: 'swiggy@upi',
            body: 'Rs.500 paid to swiggy@upi.',
          );
          expect(vpaIdentity.displayName, 'Swiggy');
        },
      );

      test(
        'ABC Bakery, ABC Electronics, and ABC Traders never collide just because they share "ABC"',
        () {
          final bakery = resolver.resolveDeterministic(
            regexMerchantText: 'ABC Bakery',
            body: 'Rs.500 paid to ABC Bakery.',
          );
          final electronics = resolver.resolveDeterministic(
            regexMerchantText: 'ABC Electronics',
            body: 'Rs.500 paid to ABC Electronics.',
          );
          expect(bakery.normalizedName, isNot(electronics.normalizedName));
          expect(bakery.displayName, 'ABC Bakery');
          expect(electronics.displayName, 'ABC Electronics');
        },
      );
    });
  });

  group('resolveWithAi', () {
    test(
      'deterministic identity always outranks AI — AI is never even consulted when already known',
      () {
        final deterministic = resolver.resolveDeterministic(
          regexMerchantText: 'swiggy@upi',
          body: 'Rs.500 paid to swiggy@upi.',
        );
        final result = resolver.resolveWithAi(
          deterministic: deterministic,
          aiMerchant: 'Some Other Name',
          aiEvidence: 'some evidence',
          aiConfidence: 0.9,
          aiMerchantTypeName: 'business',
          aiPaymentProviderName: null,
          body: 'Rs.500 paid to swiggy@upi.',
        );
        expect(
          result.displayName,
          'Swiggy',
          reason: 'deterministic wins outright',
        );
      },
    );

    test('an AI merchant guess with no quoted evidence is never trusted', () {
      final deterministic = resolver.resolveDeterministic(
        regexMerchantText: null,
        body: 'Rs.500 paid.',
      );
      final result = resolver.resolveWithAi(
        deterministic: deterministic,
        aiMerchant: 'Rahul',
        aiEvidence: null,
        aiConfidence: 0.9,
        aiMerchantTypeName: 'person',
        aiPaymentProviderName: null,
        body: 'Rs.500 paid.',
      );
      expect(
        result.isKnown,
        isFalse,
        reason: 'unevidenced AI guess must never become an identity',
      );
    });

    test(
      'an AI merchant guess WITH quoted evidence is trusted when deterministic tiers found nothing',
      () {
        final deterministic = resolver.resolveDeterministic(
          regexMerchantText: '9876543210@oksbi',
          body: 'Rs.450 paid to 9876543210@oksbi',
        );
        final result = resolver.resolveWithAi(
          deterministic: deterministic,
          aiMerchant: 'Local Kirana Store',
          // Grounded (Phase 4): quotes the VPA text that actually occurs in
          // the message, rather than a phrase invented wholesale.
          aiEvidence: 'paid to 9876543210@oksbi',
          aiConfidence: 0.7,
          aiMerchantTypeName: 'business',
          aiPaymentProviderName: null,
          body: 'Rs.450 paid to 9876543210@oksbi',
        );
        expect(result.isKnown, isTrue);
        expect(result.displayName, 'Local Kirana Store');
        expect(result.source, MerchantSource.aiInference);
        expect(result.merchantType, MerchantType.business);
      },
    );

    test(
      'REGRESSION: "₹450 paid to 9876543210@oksbi" with no AI at all stays unknown end to end',
      () {
        final deterministic = resolver.resolveDeterministic(
          regexMerchantText: '9876543210@oksbi',
          body: '₹450 paid to 9876543210@oksbi',
        );
        final result = resolver.resolveWithAi(
          deterministic: deterministic,
          aiMerchant: null,
          aiEvidence: null,
          aiConfidence: 0.0,
          aiMerchantTypeName: null,
          aiPaymentProviderName: null,
          body: '₹450 paid to 9876543210@oksbi',
        );
        expect(result.isKnown, isFalse);
        expect(result.displayName, isNull);
      },
    );

    test(
      'PHASE 4 REGRESSION: an AI merchant guess whose "evidence" does not actually occur in the message is rejected, not just when evidence is absent',
      () {
        final deterministic = resolver.resolveDeterministic(
          regexMerchantText: '9876543210@oksbi',
          body: 'Rs.500 paid to 9876543210@oksbi via UPI.',
        );
        final reasons = <String>[];
        final result = resolver.resolveWithAi(
          deterministic: deterministic,
          aiMerchant: 'Rahul',
          aiEvidence: 'paid to Rahul', // never appears in the body above
          aiConfidence: 0.9,
          aiMerchantTypeName: 'person',
          aiPaymentProviderName: null,
          body: 'Rs.500 paid to 9876543210@oksbi via UPI.',
          reasons: reasons,
        );
        expect(
          result.isKnown,
          isFalse,
          reason:
              'a hallucinated (ungrounded) quote must be treated exactly like no evidence at all',
        );
        expect(
          reasons,
          anyElement(contains('aiEvidenceNotGrounded')),
          reason: 'the rejection must be recorded, not silently dropped',
        );
      },
    );
  });
}
