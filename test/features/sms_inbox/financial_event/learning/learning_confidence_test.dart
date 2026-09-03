import 'package:finance_app/features/sms_inbox/domain/learning/learned_field.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learning_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/learning_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 1);

  group('LearningConfidence.compute', () {
    test('a field with no value has zero confidence', () {
      const field = LearnedField<String>();
      expect(LearningConfidence.compute(field: field, now: now), 0.0);
    });

    test('user-confirmed consistent history yields high confidence', () {
      final field = LearnedField<String>(
        value: 'Food & Dining',
        source: LearningSource.user,
        confirmations: 8,
        corrections: 0,
        lastUpdatedAt: now.subtract(const Duration(days: 2)),
      );
      expect(LearningConfidence.compute(field: field, now: now), 1.0);
    });

    test('a field with many corrections relative to confirmations is less confident', () {
      final consistent = LearnedField<String>(
        value: 'Shopping',
        source: LearningSource.user,
        confirmations: 8,
        corrections: 2,
        lastUpdatedAt: now,
      );
      final volatile = LearnedField<String>(
        value: 'Shopping',
        source: LearningSource.user,
        confirmations: 2,
        corrections: 8,
        lastUpdatedAt: now,
      );

      expect(
        LearningConfidence.compute(field: consistent, now: now),
        greaterThan(LearningConfidence.compute(field: volatile, now: now)),
      );
    });

    test('AI/inference sourced values are trusted less than user-sourced ones', () {
      final userField = LearnedField<String>(
        value: 'Travel',
        source: LearningSource.user,
        confirmations: 4,
        lastUpdatedAt: now,
      );
      final aiField = LearnedField<String>(
        value: 'Travel',
        source: LearningSource.ai,
        confirmations: 4,
        lastUpdatedAt: now,
      );
      final inferredField = LearnedField<String>(
        value: 'Travel',
        source: LearningSource.inference,
        confirmations: 4,
        lastUpdatedAt: now,
      );

      final userConfidence = LearningConfidence.compute(field: userField, now: now);
      final aiConfidence = LearningConfidence.compute(field: aiField, now: now);
      final inferredConfidence = LearningConfidence.compute(field: inferredField, now: now);

      expect(userConfidence, greaterThan(aiConfidence));
      expect(aiConfidence, greaterThan(inferredConfidence));
    });

    test('a stale value (untouched past staleAfter) has discounted confidence', () {
      final fresh = LearnedField<String>(
        value: 'Groceries',
        source: LearningSource.user,
        confirmations: 5,
        lastUpdatedAt: now.subtract(const Duration(days: 5)),
      );
      final stale = LearnedField<String>(
        value: 'Groceries',
        source: LearningSource.user,
        confirmations: 5,
        lastUpdatedAt: now.subtract(const Duration(days: 400)),
      );

      expect(
        LearningConfidence.compute(field: fresh, now: now),
        greaterThan(LearningConfidence.compute(field: stale, now: now)),
      );
    });
  });
}
