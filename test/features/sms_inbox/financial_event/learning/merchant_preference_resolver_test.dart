import 'package:finance_app/features/sms_inbox/domain/learning/learning_source.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_preference_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 1, 1);

  group('MerchantPreferenceResolver.resolve', () {
    test('empty history resolves to null', () {
      expect(MerchantPreferenceResolver.resolve<String>(const []), isNull);
    });

    test('a single observation wins trivially', () {
      final result = MerchantPreferenceResolver.resolve([
        MerchantFieldObservation(value: 'Food', timestamp: base, isCorrection: false),
      ]);
      expect(result!.value, 'Food');
    });

    test('most frequent value wins when there is no explicit correction', () {
      final result = MerchantPreferenceResolver.resolve([
        MerchantFieldObservation(
          value: 'Shopping',
          timestamp: base,
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Shopping',
          timestamp: base.add(const Duration(days: 1)),
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Electronics',
          timestamp: base.add(const Duration(days: 2)),
          isCorrection: false,
        ),
      ]);
      expect(result!.value, 'Shopping');
    });

    test('the most recent explicit correction wins even over older frequent history', () {
      final result = MerchantPreferenceResolver.resolve([
        MerchantFieldObservation(
          value: 'Food & Dining',
          timestamp: base,
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Food & Dining',
          timestamp: base.add(const Duration(days: 1)),
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Food & Dining',
          timestamp: base.add(const Duration(days: 2)),
          isCorrection: false,
        ),
        MerchantFieldObservation(
          value: 'Groceries',
          timestamp: base.add(const Duration(days: 30)),
          isCorrection: true,
          source: LearningSource.user,
        ),
      ]);
      expect(result!.value, 'Groceries');
      expect(result.reason, contains('correction'));
    });

    test('full history is preserved regardless of which value wins', () {
      final observations = [
        MerchantFieldObservation(value: 'A', timestamp: base, isCorrection: false),
        MerchantFieldObservation(
          value: 'B',
          timestamp: base.add(const Duration(days: 1)),
          isCorrection: true,
        ),
      ];
      final result = MerchantPreferenceResolver.resolve(observations);
      expect(result!.history.length, 2);
      expect(result.history.map((o) => o.value), containsAll(['A', 'B']));
    });
  });
}
