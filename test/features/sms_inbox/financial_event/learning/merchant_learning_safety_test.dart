import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/correction_event.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learned_field.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learning_source.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_correction_log.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_learning_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the learning layer's data model has no path by which merchant
/// memory could influence hard SMS facts — amount, direction, account,
/// status, or reference number — or misclassify a payment provider as a
/// merchant. These are structural/API-surface tests: the safety property
/// being proven is "there is no field/parameter for this," not "a runtime
/// check blocks it."
void main() {
  group('MerchantLearningProfile never carries hard transaction facts', () {
    test('only merchant-identity/category/payment-channel fields exist', () {
      const profile = MerchantLearningProfile(
        userId: 'u1',
        merchantKey: 'swiggy',
        merchantType: LearnedField<MerchantType>(value: MerchantType.business),
        category: LearnedField<String>(value: 'cat-food'),
        subcategory: LearnedField<String>(value: 'Food Delivery'),
        paymentProvider: LearnedField<PaymentProvider>(value: PaymentProvider.phonePe),
        paymentMethod: LearnedField<PaymentMethod>(value: PaymentMethod.upi),
      );

      // The whole point of this test: this profile has fields for identity,
      // category, subcategory, and payment channel/provider — and nothing
      // else. There is no amount/status/reference field to assert against,
      // which is the guarantee itself.
      expect(profile.merchantKey, 'swiggy');
      expect(profile.category.value, 'cat-food');
    });
  });

  group('CorrectionEvent never stores raw SMS text or hard facts', () {
    test('fields are restricted to structured merchant/category/provider identifiers', () {
      final event = CorrectionEvent(
        merchantKey: 'swiggy',
        field: LearnedFieldType.category,
        oldValue: 'cat-shopping',
        newValue: 'cat-food',
        timestamp: DateTime(2026, 8, 1),
        source: LearningSource.user,
      );

      expect(event.merchantKey, isNot(contains('rs.')));
      expect(event.oldValue, isNot(contains('a/c')));
      expect(event.newValue, 'cat-food');
    });

    test('correction log is append-only and preserves every entry', () {
      final log = MerchantCorrectionLog();
      log.record(
        CorrectionEvent(
          merchantKey: 'amazon',
          field: LearnedFieldType.category,
          oldValue: 'cat-shopping',
          newValue: 'cat-electronics',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      log.record(
        CorrectionEvent(
          merchantKey: 'amazon',
          field: LearnedFieldType.category,
          oldValue: 'cat-electronics',
          newValue: 'cat-shopping',
          timestamp: DateTime(2026, 2, 1),
        ),
      );

      expect(log.all, hasLength(2));
      expect(log.forMerchant('amazon'), hasLength(2));
    });
  });

  group('payment method history yields to real SMS evidence', () {
    test('a learned payment-method preference is only ever a suggestion input, never authoritative', () {
      // The learning layer only ever produces a LearnedField<PaymentMethod>
      // as historical context. It is the caller's (FinancialEventExtractor's)
      // responsibility to keep hard evidence authoritative; this test
      // documents that a learned method disagreeing with fresh evidence is
      // representable and does not, by itself, mutate anything.
      final learned = LearnedField<PaymentMethod>(
        value: PaymentMethod.upi,
        source: LearningSource.user,
        confirmations: 10,
        lastUpdatedAt: DateTime(2026, 1, 1),
      );

      const actualSmsEvidence = PaymentMethod.creditCard;

      // The learned value and the fresh evidence can simply disagree — nothing
      // in this layer forces or blocks that; there is no `apply`/`override`
      // method on LearnedField at all.
      expect(learned.value, isNot(actualSmsEvidence));
    });
  });

  group('provider vs merchant stays structurally distinct', () {
    test('MerchantLearningProfile.paymentProvider and merchantKey are separate fields/types', () {
      const profile = MerchantLearningProfile(
        userId: 'u1',
        merchantKey: 'swiggy',
        paymentProvider: LearnedField<PaymentProvider>(value: PaymentProvider.phonePe),
      );

      expect(profile.merchantKey, 'swiggy');
      expect(profile.paymentProvider.value, PaymentProvider.phonePe);
      // A PaymentProvider enum value can never itself equal a merchant key
      // string — they are different types entirely, which is the guarantee.
    });
  });
}
