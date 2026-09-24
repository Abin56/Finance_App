import 'package:finance_app/features/sms_inbox/domain/financial_event/ai_claim_validator.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/ai_evidence_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateMerchant', () {
    test(
      'THE MOTIVATING CASE: a real, grounded VPA quote does not establish an invented merchant identity',
      () {
        // "Rs.500 paid to abc123@oksbi" — the AI claims merchant "Rahul"
        // backed by the VPA text itself. The VPA genuinely occurs in the
        // message (grounding alone would accept this), but a VPA is
        // evidence of the VPA, never of who it belongs to.
        final verdict = AiClaimValidator.validateMerchant(
          claimedValue: 'Rahul',
          evidence: 'abc123@oksbi',
          evidenceType: AiEvidenceType.vpa,
          body: 'Rs.500 paid to abc123@oksbi',
        );
        expect(verdict.accepted, isFalse);
        expect(verdict.rejectionReason, contains('VPA'));
      },
    );

    test('an explicit merchant-name quote is accepted', () {
      final verdict = AiClaimValidator.validateMerchant(
        claimedValue: 'Swiggy',
        evidence: 'to Swiggy',
        evidenceType: AiEvidenceType.merchantName,
        body: 'Paid to Swiggy using PhonePe',
      );
      expect(verdict.accepted, isTrue);
    });

    test('a provider-name quote never establishes a merchant claim', () {
      final verdict = AiClaimValidator.validateMerchant(
        claimedValue: 'PhonePe',
        evidence: 'using PhonePe',
        evidenceType: AiEvidenceType.providerName,
        body: 'Rs.500 paid using PhonePe',
      );
      expect(verdict.accepted, isFalse);
      expect(verdict.rejectionReason, contains('provider'));
    });

    test('amount/account evidence types never establish a merchant claim', () {
      for (final type in [AiEvidenceType.amount, AiEvidenceType.account]) {
        final verdict = AiClaimValidator.validateMerchant(
          claimedValue: 'Some Store',
          evidence: 'Rs.500',
          evidenceType: type,
          body: 'Rs.500 debited',
        );
        expect(verdict.accepted, isFalse, reason: 'type: $type');
      }
    });

    test(
      'ungrounded evidence is rejected regardless of a strong evidence type',
      () {
        final verdict = AiClaimValidator.validateMerchant(
          claimedValue: 'Rahul',
          evidence: 'paid to Rahul',
          evidenceType: AiEvidenceType.merchantName,
          body: 'Rs.500 paid to abc123@oksbi',
        );
        expect(verdict.accepted, isFalse);
        expect(verdict.rejectionReason, contains('does not occur'));
      },
    );

    test('a contextual phrase is accepted (weaker, but not rejected)', () {
      final verdict = AiClaimValidator.validateMerchant(
        claimedValue: 'the corner store',
        evidence: 'at the corner store',
        evidenceType: AiEvidenceType.contextualPhrase,
        body: 'Rs.500 paid at the corner store',
      );
      expect(verdict.accepted, isTrue);
    });

    test('no claim at all is rejected', () {
      final verdict = AiClaimValidator.validateMerchant(
        claimedValue: null,
        evidence: null,
        evidenceType: AiEvidenceType.unknown,
        body: 'Rs.500 debited',
      );
      expect(verdict.accepted, isFalse);
    });
  });

  group('validateMerchantType', () {
    test('mirrors validateMerchant\'s VPA rejection', () {
      final verdict = AiClaimValidator.validateMerchantType(
        claimedValue: 'person',
        evidence: 'abc123@oksbi',
        evidenceType: AiEvidenceType.vpa,
        body: 'Rs.500 paid to abc123@oksbi',
      );
      expect(verdict.accepted, isFalse);
    });
  });

  group('validateCategory', () {
    test('a merchant-name quote supports a category claim', () {
      final verdict = AiClaimValidator.validateCategory(
        claimedValue: 'Food & Dining',
        evidence: 'to Swiggy',
        evidenceType: AiEvidenceType.merchantName,
        body: 'Paid to Swiggy',
      );
      expect(verdict.accepted, isTrue);
    });

    test('a contextual phrase supports a category claim', () {
      final verdict = AiClaimValidator.validateCategory(
        claimedValue: 'Food & Dining',
        evidence: 'a restaurant order',
        evidenceType: AiEvidenceType.contextualPhrase,
        body: 'Rs.500 paid for a restaurant order',
      );
      expect(verdict.accepted, isTrue);
    });

    test(
      'PAYMENT RAIL ALONE IS INVALID: a provider-name quote never supports a category claim',
      () {
        final verdict = AiClaimValidator.validateCategory(
          claimedValue: 'Shopping',
          evidence: 'using PhonePe',
          evidenceType: AiEvidenceType.providerName,
          body: 'Rs.500 paid using PhonePe',
        );
        expect(verdict.accepted, isFalse);
        expect(verdict.rejectionReason, contains('not a spending category'));
      },
    );

    test('a bare VPA quote never supports a category claim', () {
      final verdict = AiClaimValidator.validateCategory(
        claimedValue: 'Food & Dining',
        evidence: 'abc123@oksbi',
        evidenceType: AiEvidenceType.vpa,
        body: 'Rs.500 paid to abc123@oksbi',
      );
      expect(verdict.accepted, isFalse);
    });
  });

  group('validatePaymentProvider', () {
    test('an explicit "using PhonePe" phrase is accepted', () {
      final verdict = AiClaimValidator.validatePaymentProvider(
        claimedValue: 'phonePe',
        evidence: 'using PhonePe',
        evidenceType: AiEvidenceType.providerName,
        body: 'Rs.500 paid using PhonePe',
      );
      expect(verdict.accepted, isTrue);
    });

    test('a bare VPA is never enough to establish a provider claim', () {
      final verdict = AiClaimValidator.validatePaymentProvider(
        claimedValue: 'phonePe',
        evidence: 'xyz@oksbi',
        evidenceType: AiEvidenceType.vpa,
        body: 'Rs.500 paid to xyz@oksbi',
      );
      expect(verdict.accepted, isFalse);
    });

    test(
      'a merchant-name quote is never enough to establish a provider claim',
      () {
        final verdict = AiClaimValidator.validatePaymentProvider(
          claimedValue: 'phonePe',
          evidence: 'to Swiggy',
          evidenceType: AiEvidenceType.merchantName,
          body: 'Rs.500 paid to Swiggy',
        );
        expect(verdict.accepted, isFalse);
      },
    );
  });
}
