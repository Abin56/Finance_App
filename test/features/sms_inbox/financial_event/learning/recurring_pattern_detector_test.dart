import 'package:finance_app/features/sms_inbox/domain/learning/recurring_pattern.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecurringPatternDetector.detect', () {
    test('detects a monthly subscription pattern', () {
      final records = [
        MerchantTransactionRecord(
          merchantKey: 'netflix',
          amount: 199,
          date: DateTime(2026, 1, 5),
        ),
        MerchantTransactionRecord(
          merchantKey: 'netflix',
          amount: 199,
          date: DateTime(2026, 2, 5),
        ),
        MerchantTransactionRecord(
          merchantKey: 'netflix',
          amount: 199,
          date: DateTime(2026, 3, 6),
        ),
        MerchantTransactionRecord(
          merchantKey: 'netflix',
          amount: 199,
          date: DateTime(2026, 4, 5),
        ),
      ];

      final patterns = RecurringPatternDetector.detect(records);

      expect(patterns, hasLength(1));
      expect(patterns.first.merchantKey, 'netflix');
      expect(patterns.first.occurrences, 4);
      expect(patterns.first.intervalDays, closeTo(30, 3));
    });

    test('does not report a pattern from irregular one-off spends', () {
      final records = [
        MerchantTransactionRecord(
          merchantKey: 'swiggy',
          amount: 350,
          date: DateTime(2026, 1, 2),
        ),
        MerchantTransactionRecord(
          merchantKey: 'swiggy',
          amount: 620,
          date: DateTime(2026, 1, 9),
        ),
        MerchantTransactionRecord(
          merchantKey: 'swiggy',
          amount: 210,
          date: DateTime(2026, 1, 25),
        ),
      ];

      final patterns = RecurringPatternDetector.detect(records);
      expect(patterns, isEmpty);
    });

    test('does not report a pattern below minOccurrences', () {
      final records = [
        MerchantTransactionRecord(
          merchantKey: 'spotify',
          amount: 119,
          date: DateTime(2026, 1, 1),
        ),
        MerchantTransactionRecord(
          merchantKey: 'spotify',
          amount: 119,
          date: DateTime(2026, 2, 1),
        ),
      ];

      final patterns = RecurringPatternDetector.detect(records);
      expect(patterns, isEmpty);
    });

    test('separates different merchants independently', () {
      final records = [
        MerchantTransactionRecord(
          merchantKey: 'netflix',
          amount: 199,
          date: DateTime(2026, 1, 5),
        ),
        MerchantTransactionRecord(
          merchantKey: 'netflix',
          amount: 199,
          date: DateTime(2026, 2, 5),
        ),
        MerchantTransactionRecord(
          merchantKey: 'netflix',
          amount: 199,
          date: DateTime(2026, 3, 5),
        ),
        MerchantTransactionRecord(
          merchantKey: 'spotify',
          amount: 119,
          date: DateTime(2026, 1, 1),
        ),
      ];

      final patterns = RecurringPatternDetector.detect(records);
      expect(patterns.map((p) => p.merchantKey), ['netflix']);
    });
  });
}
