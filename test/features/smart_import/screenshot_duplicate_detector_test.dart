import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/smart_import/domain/screenshot_duplicate_detector.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedTransaction _detected({
  String id = 'row-1',
  int sourceImageIndex = 0,
  DateTime? date,
  String? description,
  double? amount,
  TransactionType type = TransactionType.expense,
}) {
  return DetectedTransaction(
    id: id,
    sourceImageIndex: sourceImageIndex,
    rawText: '',
    date: date,
    rawDescription: description,
    amount: amount,
    type: type,
  );
}

Transaction _existing({
  required DateTime dateTime,
  required String description,
  required double amount,
  String accountId = 'acc-1',
  TransactionType type = TransactionType.expense,
}) {
  return Transaction(
    id: 'existing-1',
    type: type,
    amount: amount,
    dateTime: dateTime,
    accountId: accountId,
    categoryId: 'cat-1',
    description: description,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('ScreenshotDuplicateDetector', () {
    test('flags a match even when merchant text differs slightly', () {
      final existing = [
        _existing(
          dateTime: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 420,
        ),
      ];
      final detected = [
        _detected(
          date: DateTime(2026, 9, 5),
          description: 'SWIGGY FOOD',
          amount: 420.00,
        ),
      ];

      ScreenshotDuplicateDetector.apply(detected, existing);

      expect(detected.single.isDuplicate, isTrue);
      expect(detected.single.duplicateTransactionId, 'existing-1');
      expect(detected.single.isSelected, isFalse);
    });

    test('does not flag a different amount as a duplicate', () {
      final existing = [
        _existing(
          dateTime: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 420,
        ),
      ];
      final detected = [
        _detected(
          date: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 399,
        ),
      ];

      ScreenshotDuplicateDetector.apply(detected, existing);

      expect(detected.single.isDuplicate, isFalse);
    });

    test(
      'does not flag a completely different merchant on the same day/amount',
      () {
        final existing = [
          _existing(
            dateTime: DateTime(2026, 9, 5),
            description: 'SWIGGY',
            amount: 420,
          ),
        ];
        final detected = [
          _detected(
            date: DateTime(2026, 9, 5),
            description: 'UBER',
            amount: 420,
          ),
        ];

        ScreenshotDuplicateDetector.apply(detected, existing);

        expect(detected.single.isDuplicate, isFalse);
      },
    );

    test('tolerates a one-day date difference', () {
      final existing = [
        _existing(
          dateTime: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 420,
        ),
      ];
      final detected = [
        _detected(
          date: DateTime(2026, 9, 6),
          description: 'SWIGGY',
          amount: 420,
        ),
      ];

      ScreenshotDuplicateDetector.apply(detected, existing);

      expect(detected.single.isDuplicate, isTrue);
    });

    test('restricts comparison to the given account when one is provided', () {
      final existing = [
        _existing(
          dateTime: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 420,
          accountId: 'acc-other',
        ),
      ];
      final detected = [
        _detected(
          date: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 420,
        ),
      ];

      ScreenshotDuplicateDetector.apply(detected, existing, accountId: 'acc-1');

      expect(detected.single.isDuplicate, isFalse);
    });

    test('an acknowledged duplicate stays selected across a re-check', () {
      final existing = [
        _existing(
          dateTime: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 420,
        ),
      ];
      final detected = [
        _detected(
            date: DateTime(2026, 9, 5),
            description: 'SWIGGY',
            amount: 420,
          )
          ..duplicateAcknowledged = true
          ..isSelected = true,
      ];

      ScreenshotDuplicateDetector.apply(detected, existing);

      expect(detected.single.isDuplicate, isTrue);
      expect(detected.single.isSelected, isTrue);
    });

    test('never flags a row with no date or amount', () {
      final existing = [
        _existing(
          dateTime: DateTime(2026, 9, 5),
          description: 'SWIGGY',
          amount: 420,
        ),
      ];
      final detected = [_detected(description: 'SWIGGY')];

      ScreenshotDuplicateDetector.apply(detected, existing);

      expect(detected.single.isDuplicate, isFalse);
    });

    group('within the same batch (e.g. two overlapping screenshots)', () {
      test(
        'flags the second occurrence of the same transaction, not the first',
        () {
          final detected = [
            _detected(
              id: 'a',
              sourceImageIndex: 0,
              date: DateTime(2026, 9, 5),
              description: 'SWIGGY',
              amount: 420,
            ),
            _detected(
              id: 'b',
              sourceImageIndex: 1,
              date: DateTime(2026, 9, 5),
              description: 'SWIGGY FOOD',
              amount: 420,
            ),
          ];

          ScreenshotDuplicateDetector.apply(detected, const []);

          expect(
            detected[0].isDuplicate,
            isFalse,
            reason: 'the first occurrence stays clean',
          );
          expect(detected[1].isDuplicate, isTrue);
          expect(
            detected[1].duplicateTransactionId,
            isNull,
            reason:
                'no real Transaction id — the match is another detected row',
          );
          expect(detected[1].isSelected, isFalse);
        },
      );

      test(
        'does not flag two legitimately different transactions with different amounts',
        () {
          final detected = [
            _detected(
              id: 'a',
              date: DateTime(2026, 9, 5),
              description: 'SWIGGY',
              amount: 420,
            ),
            _detected(
              id: 'b',
              date: DateTime(2026, 9, 5),
              description: 'SWIGGY',
              amount: 210,
            ),
          ];

          ScreenshotDuplicateDetector.apply(detected, const []);

          expect(detected[0].isDuplicate, isFalse);
          expect(detected[1].isDuplicate, isFalse);
        },
      );

      test(
        'a within-batch duplicate can also be overridden with "Import anyway"',
        () {
          final detected = [
            _detected(
              id: 'a',
              date: DateTime(2026, 9, 5),
              description: 'SWIGGY',
              amount: 420,
            ),
            _detected(
                id: 'b',
                date: DateTime(2026, 9, 5),
                description: 'SWIGGY',
                amount: 420,
              )
              ..duplicateAcknowledged = true
              ..isSelected = true,
          ];

          ScreenshotDuplicateDetector.apply(detected, const []);

          expect(detected[1].isDuplicate, isTrue);
          expect(detected[1].isSelected, isTrue);
        },
      );

      test(
        'an existing-Transaction match takes priority over a within-batch match',
        () {
          final existing = [
            _existing(
              dateTime: DateTime(2026, 9, 5),
              description: 'SWIGGY',
              amount: 420,
            ),
          ];
          final detected = [
            _detected(
              id: 'a',
              date: DateTime(2026, 9, 5),
              description: 'SWIGGY',
              amount: 420,
            ),
            _detected(
              id: 'b',
              date: DateTime(2026, 9, 5),
              description: 'SWIGGY',
              amount: 420,
            ),
          ];

          ScreenshotDuplicateDetector.apply(detected, existing);

          // Both match the real transaction directly, so both point to it —
          // neither is merely "the same as another detected row".
          expect(detected[0].duplicateTransactionId, 'existing-1');
          expect(detected[1].duplicateTransactionId, 'existing-1');
        },
      );
    });
  });
}
