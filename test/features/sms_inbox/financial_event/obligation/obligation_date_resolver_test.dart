import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_date_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tue 1 Sep 2026, 10:00 — a fixed, hand-verifiable anchor.
  final reference = DateTime(2026, 9, 1, 10);

  group('unknown stays unknown', () {
    test('a message with no date phrase at all resolves to unknown', () {
      final result = ObligationDateResolver.resolve(
        'Your loan installment is pending, please pay soon.',
        referenceDate: reference,
      );
      expect(result.isKnown, isFalse);
      expect(result.kind, ObligationDateKind.unknown);
    });

    test('a vague recurring phrase with no concrete date stays unknown', () {
      final result = ObligationDateResolver.resolve(
        'Your rent is due on the 1st of every month.',
        referenceDate: reference,
      );
      expect(
        result.isKnown,
        isFalse,
        reason: 'No day+month-name pair is present — must not be guessed.',
      );
    });
  });

  group('relative dates', () {
    test('today', () {
      final result = ObligationDateResolver.resolve(
        'Payment due today.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 1));
    });

    test('tomorrow', () {
      final result = ObligationDateResolver.resolve(
        'Your EMI will be debited tomorrow.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 2, 10));
      expect(result.kind, ObligationDateKind.scheduledDebitDate);
    });

    test('day after tomorrow', () {
      final result = ObligationDateResolver.resolve(
        'Your bill is due day after tomorrow.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 3, 10));
    });

    test('in N days', () {
      final result = ObligationDateResolver.resolve(
        'Your credit card bill is due in 5 days.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 6, 10));
      expect(result.kind, ObligationDateKind.dueDate);
    });

    test('within N hours', () {
      final result = ObligationDateResolver.resolve(
        'Please pay within 48 hours.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 3, 10));
      expect(result.kind, ObligationDateKind.paymentDeadline);
    });

    test('next <weekday> resolves to the next occurrence, never today', () {
      // 1 Sep 2026 is a Tuesday.
      expect(reference.weekday, DateTime.tuesday);
      final result = ObligationDateResolver.resolve(
        'Due next Tuesday.',
        referenceDate: reference,
      );
      // Next Tuesday from a Tuesday must be 7 days out, not 0.
      expect(result.value, DateTime(2026, 9, 8));
    });

    test('next Monday from a Tuesday resolves 6 days out', () {
      final result = ObligationDateResolver.resolve(
        'Due next Monday.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 7));
    });
  });

  group('absolute dates', () {
    test('day + full month name + explicit year', () {
      final result = ObligationDateResolver.resolve(
        'Due on 5 September 2026.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 5));
    });

    test('day + abbreviated month, no year, defaults to reference year', () {
      final result = ObligationDateResolver.resolve(
        'Due on 10 Oct.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 10, 10));
    });

    test('ordinal suffix does not break parsing', () {
      final result = ObligationDateResolver.resolve(
        'Due on 3rd Sep.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 3));
    });

    test('a bare day+month far in the past rolls forward to next year', () {
      final decemberReference = DateTime(2025, 12, 20, 10);
      final result = ObligationDateResolver.resolve(
        'Your credit card payment is due on 5 Jan.',
        referenceDate: decemberReference,
      );
      expect(
        result.value,
        DateTime(2026, 1, 5),
        reason:
            '5 Jan 2025 would be ~11 months in the past relative to 20 Dec 2025 — must roll to 2026, not silently mean a stale past date.',
      );
    });

    test('a bare day+month close to reference stays in the current year', () {
      final result = ObligationDateResolver.resolve(
        'Due on 5 Sep.',
        referenceDate: reference,
      );
      expect(result.value, DateTime(2026, 9, 5));
    });
  });

  group('date kind classification', () {
    test('"due on" resolves to dueDate kind', () {
      final result = ObligationDateResolver.resolve(
        'Payment due on 5 Sep.',
        referenceDate: reference,
      );
      expect(result.kind, ObligationDateKind.dueDate);
    });

    test('"will be debited on" resolves to scheduledDebitDate kind', () {
      final result = ObligationDateResolver.resolve(
        'Amount will be debited on 5 Sep.',
        referenceDate: reference,
      );
      expect(result.kind, ObligationDateKind.scheduledDebitDate);
    });

    test('"before"/"by" resolves to paymentDeadline kind', () {
      final result = ObligationDateResolver.resolve(
        'Please pay by 5 Sep.',
        referenceDate: reference,
      );
      expect(result.kind, ObligationDateKind.paymentDeadline);
    });

    test('"expires on" resolves to expiryDate kind', () {
      final result = ObligationDateResolver.resolve(
        'Your recharge expires on 5 Sep.',
        referenceDate: reference,
      );
      expect(result.kind, ObligationDateKind.expiryDate);
    });
  });

  test('multiple dates in one message resolves the first concrete one', () {
    final result = ObligationDateResolver.resolve(
      'Your subscription renews on 5 Sep, and your bill is due on 10 Sep.',
      referenceDate: reference,
    );
    expect(result.value, DateTime(2026, 9, 5));
  });

  test('evidence always names the matched substring, never fabricated', () {
    final result = ObligationDateResolver.resolve(
      'Due on 5 Sep.',
      referenceDate: reference,
    );
    expect(result.evidence, isNotNull);
    expect(result.evidence!.toLowerCase(), contains('5 sep'));
  });
}
