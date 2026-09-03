import 'package:finance_app/features/sms_inbox/domain/learning/ai_call_reduction_decision.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learned_field.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learning_source.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_preference_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 1);

  group('AiCallReductionDecider.decide', () {
    test('first-time / unknown merchant always calls AI', () {
      final decision = AiCallReductionDecider.decide(
        merchantKey: null,
        categoryField: const LearnedField<String>(),
        categoryObservations: const [],
        now: now,
      );

      expect(decision.shouldCallAi, isTrue);
      expect(decision.reason, AiCallReductionReason.unknownMerchant);
      expect(decision.confidence, 0.0);
    });

    test('known merchant with no history but with a recurring pattern skips AI', () {
      final decision = AiCallReductionDecider.decide(
        merchantKey: 'netflix',
        categoryField: const LearnedField<String>(),
        categoryObservations: const [],
        now: now,
        hasStrongRecurringPattern: true,
      );

      expect(decision.shouldCallAi, isFalse);
      expect(decision.reason, AiCallReductionReason.strongPattern);
    });

    test('strong, consistent user history skips AI and explains why', () {
      final field = LearnedField<String>(
        value: 'Food & Dining',
        source: LearningSource.user,
        confirmations: 8,
        lastUpdatedAt: now.subtract(const Duration(days: 3)),
      );
      final observations = List.generate(
        8,
        (i) => MerchantFieldObservation(
          value: 'Food & Dining',
          timestamp: now.subtract(Duration(days: 60 - i * 5)),
          isCorrection: false,
          source: LearningSource.user,
        ),
      );

      final decision = AiCallReductionDecider.decide(
        merchantKey: 'swiggy',
        categoryField: field,
        categoryObservations: observations,
        now: now,
      );

      expect(decision.shouldCallAi, isFalse);
      expect(decision.reason, AiCallReductionReason.userHistory);
      expect(decision.explanation, contains('previous'));
      expect(decision.explanation, contains('8'));
    });

    test('a recent explicit correction is trusted immediately, ahead of older history', () {
      final field = LearnedField<String>(
        value: 'Groceries',
        source: LearningSource.user,
        confirmations: 0,
        corrections: 1,
        lastUpdatedAt: now.subtract(const Duration(days: 1)),
      );
      final observations = [
        MerchantFieldObservation(
          value: 'Shopping',
          timestamp: now.subtract(const Duration(days: 200)),
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Groceries',
          timestamp: now.subtract(const Duration(days: 1)),
          isCorrection: true,
          source: LearningSource.user,
        ),
      ];

      final decision = AiCallReductionDecider.decide(
        merchantKey: 'amazon',
        categoryField: field,
        categoryObservations: observations,
        now: now,
      );

      expect(decision.shouldCallAi, isFalse);
      expect(decision.reason, AiCallReductionReason.recentCorrection);
      expect(decision.source, LearningSource.user);
    });

    test('conflicting near-equal history calls AI rather than guessing', () {
      final field = LearnedField<String>(
        value: 'Shopping',
        source: LearningSource.user,
        confirmations: 3,
        lastUpdatedAt: now.subtract(const Duration(days: 10)),
      );
      final observations = [
        MerchantFieldObservation(
          value: 'Shopping',
          timestamp: now.subtract(const Duration(days: 90)),
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Electronics',
          timestamp: now.subtract(const Duration(days: 60)),
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Shopping',
          timestamp: now.subtract(const Duration(days: 30)),
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Electronics',
          timestamp: now.subtract(const Duration(days: 10)),
          isCorrection: false,
        ),
      ];

      final decision = AiCallReductionDecider.decide(
        merchantKey: 'amazon',
        categoryField: field,
        categoryObservations: observations,
        now: now,
      );

      expect(decision.shouldCallAi, isTrue);
      expect(decision.reason, AiCallReductionReason.conflictingEvidence);
    });

    test('weak/low-confidence history still calls AI', () {
      final field = LearnedField<String>(
        value: 'Other',
        source: LearningSource.inference,
        confirmations: 1,
        corrections: 1,
        lastUpdatedAt: now.subtract(const Duration(days: 200)),
      );
      final observations = [
        MerchantFieldObservation(
          value: 'Other',
          timestamp: now.subtract(const Duration(days: 200)),
          isCorrection: false,
          source: LearningSource.inference,
        ),
      ];

      final decision = AiCallReductionDecider.decide(
        merchantKey: 'unknown-merchant-xyz',
        categoryField: field,
        categoryObservations: observations,
        now: now,
      );

      expect(decision.shouldCallAi, isTrue);
      expect(decision.reason, AiCallReductionReason.insufficientConfidence);
    });

    test('decision API surface never exposes amount/direction/account/status/reference fields', () {
      // Documented via the API itself: `decide` only accepts merchantKey,
      // a category LearnedField, category observations, now, and a
      // recurring-pattern flag — there is no parameter through which hard
      // SMS evidence could reach this decision. This test exists so a
      // future edit that adds such a parameter fails a code-review nudge
      // rather than silently widening the surface.
      expect(
        AiCallReductionDecider.decide(
          merchantKey: 'swiggy',
          categoryField: const LearnedField<String>(),
          categoryObservations: const [],
          now: now,
        ),
        isA<AiCallReductionDecision>(),
      );
    });
  });
}
