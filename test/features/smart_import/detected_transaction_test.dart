import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedTransaction _row({
  bool includeDate = true,
  String? description = 'Swiggy',
  double? amount = 420,
}) {
  return DetectedTransaction(
    id: 'row-1',
    sourceImageIndex: 0,
    rawText: '',
    date: includeDate ? DateTime(2026, 9, 5) : null,
    rawDescription: description,
    amount: amount,
    type: TransactionType.expense,
  );
}

void main() {
  group('DetectedTransaction review validation', () {
    test('a fully-populated row is ready', () {
      final row = _row();
      expect(row.hasRequiredFields, isTrue);
      expect(row.reviewStatus, DetectionReviewStatus.ready);
    });

    test('a missing date forces review', () {
      final row = _row(includeDate: false);
      expect(row.hasRequiredFields, isFalse);
      expect(row.reviewStatus, DetectionReviewStatus.needsReview);
    });

    test('a missing amount forces review', () {
      final row = _row(amount: null);
      expect(row.hasRequiredFields, isFalse);
    });

    test('a zero amount is treated as invalid and forces review', () {
      final row = _row(amount: 0);
      expect(row.hasRequiredFields, isFalse);
    });

    test('a negative amount is treated as invalid and forces review', () {
      final row = _row(amount: -50);
      expect(row.hasRequiredFields, isFalse);
    });

    test('a missing description falls back to "Unknown" and forces review', () {
      final row = _row(description: null);
      expect(row.description, 'Unknown');
      expect(row.hasRequiredFields, isFalse);
    });

    test('a blank description also forces review', () {
      final row = _row(description: '   ');
      expect(row.description, 'Unknown');
      expect(row.hasRequiredFields, isFalse);
    });

    test('an undetected type does not by itself force review', () {
      final row = DetectedTransaction(
        id: 'row-2',
        sourceImageIndex: 0,
        rawText: '',
        date: DateTime(2026, 9, 5),
        rawDescription: 'Swiggy',
        amount: 420,
        type: null,
      );
      expect(row.hasRequiredFields, isTrue);
    });
  });

  group('DetectedTransaction.missingFieldsSummary', () {
    test('is null for a ready row', () {
      expect(_row().missingFieldsSummary, isNull);
    });

    test('names a single missing field', () {
      expect(_row(includeDate: false).missingFieldsSummary, 'Missing date');
    });

    test('names every missing field together', () {
      final row = _row(includeDate: false, amount: null, description: null);
      expect(row.missingFieldsSummary, 'Missing date, amount, description');
    });
  });
}
