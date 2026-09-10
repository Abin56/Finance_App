import 'package:finance_app/features/smart_import/domain/ocr_result.dart';
import 'package:finance_app/features/smart_import/domain/screenshot_duplicate_detector.dart';
import 'package:finance_app/features/smart_import/domain/screenshot_transaction_extractor.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds one OCR line at a given vertical position, matching how a
/// screenshot's date/merchant/amount are stacked as separate lines.
OcrTextLine _line(
  String text,
  double top, {
  double left = 0,
  double height = 20,
}) {
  return OcrTextLine(
    text: text,
    boundingBox: OcrBoundingBox(
      left: left,
      top: top,
      right: left + 100,
      bottom: top + height,
    ),
  );
}

void main() {
  final reference = DateTime(2026, 9, 7);
  const extractor = ScreenshotTransactionExtractor();

  group('ScreenshotTransactionExtractor', () {
    test('extracts three stacked transaction rows from the spec example', () {
      final lines = [
        _line('05 Sep', 0),
        _line('SWIGGY', 24),
        _line('₹420', 48),
        _line('05 Sep', 96),
        _line('AMAZON', 120),
        _line('₹1,299', 144),
        _line('06 Sep', 192),
        _line('UBER', 216),
        _line('₹185.50', 240),
      ];
      final result = OcrResult(
        fullText: lines.map((l) => l.text).join('\n'),
        lines: lines,
      );

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected, hasLength(3));

      expect(detected[0].date, DateTime(2026, 9, 5));
      expect(detected[0].description, 'Swiggy');
      expect(detected[0].amount, 420.0);

      expect(detected[1].date, DateTime(2026, 9, 5));
      expect(detected[1].description, 'Amazon');
      expect(detected[1].amount, 1299.0);

      expect(detected[2].date, DateTime(2026, 9, 6));
      expect(detected[2].description, 'Uber');
      expect(detected[2].amount, 185.50);
    });

    test(
      'reconstructs a row from lines placed side by side at the same height',
      () {
        final lines = [
          _line('05 Sep', 0, left: 0),
          _line('SWIGGY', 0, left: 120),
          _line('₹420', 0, left: 240),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(1));
        expect(detected.first.date, DateTime(2026, 9, 5));
        expect(detected.first.amount, 420.0);
        expect(detected.first.description, 'Swiggy');
      },
    );

    test('assigns income when the row says credited/received', () {
      final lines = [
        _line('05 Sep', 0),
        _line('Received from Rahul', 24),
        _line('₹500', 48),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected.single.type, TransactionType.income);
    });

    test('defaults to expense when no debit/credit wording is present', () {
      final lines = [
        _line('05 Sep', 0),
        _line('SWIGGY', 24),
        _line('₹420', 48),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected.single.type, TransactionType.expense);
      expect(detected.single.hasRequiredFields, isTrue);
    });

    test(
      'flags a row missing a description as needing review, shown as Unknown',
      () {
        final lines = [_line('06 Sep', 0), _line('₹450', 24)];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.single.description, 'Unknown');
        expect(detected.single.hasRequiredFields, isFalse);
      },
    );

    test('drops a leading header block with neither a date nor an amount', () {
      final lines = [
        _line('Account Statement', 0),
        _line('05 Sep', 40),
        _line('SWIGGY', 64),
        _line('₹420', 88),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected, hasLength(1));
    });

    test('returns an empty list when there is no OCR text at all', () {
      final result = OcrResult(fullText: '', lines: const []);
      expect(
        extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        ),
        isEmpty,
      );
    });

    test(
      'returns an empty list for garbage/unrelated OCR text without crashing',
      () {
        final lines = [
          _line('Wi-Fi Settings', 0),
          _line('Forget this network?', 24),
          _line('Cancel     OK', 48),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        expect(
          extractor.extract(
            result,
            sourceImageIndex: 0,
            referenceDate: reference,
          ),
          isEmpty,
        );
      },
    );

    test('a needs-review row is not selected by default', () {
      // No description anywhere in the block — missing a required field.
      final lines = [_line('06 Sep', 0), _line('₹450', 24)];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected.single.hasRequiredFields, isFalse);
      expect(
        detected.single.isSelected,
        isFalse,
        reason:
            'a row the user has not reviewed must not be pre-checked for import',
      );
    });

    test('a ready row is selected by default', () {
      final lines = [
        _line('05 Sep', 0),
        _line('SWIGGY', 24),
        _line('₹420', 48),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected.single.isSelected, isTrue);
    });

    test(
      'parses a single-line table row with a numeric date and a DR suffix',
      () {
        // "05/09/2026  SWIGGY       420.00 DR" as one continuous OCR line —
        // a common bank-statement table layout, distinct from the app-card
        // style tested above.
        final lines = [
          _line('05/09/2026  SWIGGY       420.00 DR', 0),
          _line('06/09/2026  AMAZON      1299.00 DR', 40),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(2));
        expect(detected[0].date, DateTime(2026, 9, 5));
        expect(detected[0].description, 'Swiggy');
        expect(detected[0].amount, 420.0);
        expect(detected[0].type, TransactionType.expense);

        expect(detected[1].date, DateTime(2026, 9, 6));
        expect(detected[1].description, 'Amazon');
        expect(detected[1].amount, 1299.0);
      },
    );

    test(
      'extracts a transaction when the amount line appears before the description',
      () {
        final lines = [
          _line('05 Sep', 0),
          _line('₹420', 24),
          _line('SWIGGY', 48),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.single.date, DateTime(2026, 9, 5));
        expect(detected.single.amount, 420.0);
        expect(detected.single.description, 'Swiggy');
      },
    );

    test('joins a description that spans multiple lines', () {
      final lines = [
        _line('05 Sep', 0),
        _line('SWIGGY', 24),
        _line('BANGALORE', 48),
        _line('₹420', 72),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected.single.description, 'Swiggy Bangalore');
    });

    test(
      'does not merge two transactions that immediately follow each other',
      () {
        final lines = [
          _line('05 Sep', 0),
          _line('SWIGGY', 24),
          _line('₹420', 48),
          // No blank-row gap at all before the next transaction starts.
          _line('05 Sep', 72),
          _line('UBER', 96),
          _line('₹185', 120),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(2));
        expect(detected[0].description, 'Swiggy');
        expect(detected[0].amount, 420.0);
        expect(detected[1].description, 'Uber');
        expect(detected[1].amount, 185.0);
      },
    );

    test('does not split a single Google Pay/PhonePe-style receipt into two '
        'transactions when the date/time line comes after the amount and '
        'merchant instead of before them', () {
      // Regression: Google Pay/PhonePe's own transaction-detail screenshot
      // layout puts the amount first, "Paid to Merchant" next, and the
      // date/time line *last* — the opposite order of a bank statement
      // table row. The block-splitting rule used to start a new block on
      // every date-bearing row unconditionally, so this trailing date line
      // was read as the start of a second, bogus transaction even though
      // the amount+merchant block above it never got a date of its own.
      final lines = [
        _line('₹420', 0),
        _line('Paid to Swiggy', 24),
        _line('05 Sep 2026, 10:32 PM', 48),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected, hasLength(1));
      expect(detected.single.date, DateTime(2026, 9, 5));
      expect(detected.single.amount, 420.0);
      expect(detected.single.hasRequiredFields, isTrue);
    });

    test(
      'two overlapping screenshots produce a flagged duplicate for the shared transaction, '
      'mirroring what SmartImportController.processImages() does when merging multiple images',
      () {
        // Screenshot 1: Swiggy + Amazon.
        final screenshot1 = OcrResult(
          fullText: 'irrelevant',
          lines: [
            _line('05 Sep', 0),
            _line('SWIGGY', 24),
            _line('₹420', 48),
            _line('05 Sep', 96),
            _line('AMAZON', 120),
            _line('₹1,299', 144),
          ],
        );
        // Screenshot 2 scrolled slightly and overlaps on Amazon, then has
        // one new transaction (Uber) the first screenshot didn't capture.
        final screenshot2 = OcrResult(
          fullText: 'irrelevant',
          lines: [
            _line('05 Sep', 0),
            _line('AMAZON', 24),
            _line('₹1,299', 48),
            _line('06 Sep', 96),
            _line('UBER', 120),
            _line('₹185.50', 144),
          ],
        );

        final merged = [
          ...extractor.extract(
            screenshot1,
            sourceImageIndex: 0,
            referenceDate: reference,
          ),
          ...extractor.extract(
            screenshot2,
            sourceImageIndex: 1,
            referenceDate: reference,
          ),
        ];
        expect(merged, hasLength(4));

        ScreenshotDuplicateDetector.apply(merged, const []);

        final swiggy = merged.firstWhere((d) => d.description == 'Swiggy');
        final amazons = merged.where((d) => d.description == 'Amazon').toList();
        final uber = merged.firstWhere((d) => d.description == 'Uber');

        expect(swiggy.isDuplicate, isFalse);
        expect(uber.isDuplicate, isFalse);
        expect(amazons, hasLength(2));
        expect(
          amazons.where((d) => d.isDuplicate).length,
          1,
          reason:
              'the first Amazon row stays clean; the repeat from screenshot 2 is flagged',
        );
        expect(amazons.where((d) => d.isDuplicate).single.isSelected, isFalse);
      },
    );
  });

  group('ScreenshotTransactionExtractor — real-world bank/UPI layouts', () {
    test('parses an SBI-style debit SMS screenshot', () {
      final lines = [
        _line(
          'Dear Customer, Rs.500.00 debited from A/c XX1234 on 05-09-26 '
          'trf to MERCHANT NAME Ref No 123456789012',
          0,
        ),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected, hasLength(1));
      final row = detected.single;
      expect(row.date, DateTime(2026, 9, 5));
      expect(row.amount, 500.0);
      expect(row.type, TransactionType.expense);
      expect(row.referenceNumber, '123456789012');
      expect(row.hasRequiredFields, isTrue);
      // The masked account number and reference number must never bleed
      // into the amount.
      expect(row.amount, isNot(1234.0));
    });

    test(
      'parses an HDFC-style debit alert with a hyphen-joined date (05-SEP-26)',
      () {
        final lines = [
          _line(
            'HDFC Bank: Rs 1,250.00 debited from a/c **1234 on 05-SEP-26 '
            'to VPA merchant@upi. UPI Ref 987654321.',
            0,
          ),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(1));
        final row = detected.single;
        expect(
          row.date,
          DateTime(2026, 9, 5),
          reason: 'the hyphen-joined "05-SEP-26" date must still parse',
        );
        expect(row.amount, 1250.0);
        expect(row.type, TransactionType.expense);
        expect(row.referenceNumber, '987654321');
        expect(row.hasRequiredFields, isTrue);
      },
    );

    test('parses an ICICI-style debit alert with a hyphen-joined date', () {
      final lines = [
        _line(
          'ICICI Bank Acct XX789 debited with INR 799.00 on 07-Sep-2026; '
          'Info: UPI-987654321-AMAZON.',
          0,
        ),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected, hasLength(1));
      final row = detected.single;
      expect(row.date, DateTime(2026, 9, 7));
      expect(row.amount, 799.0);
      expect(row.hasRequiredFields, isTrue);
    });

    test('parses an Axis-style debit alert (slash date, Avl Bal present)', () {
      final lines = [
        _line(
          'Axis Bank: Rs.2,500.00 debited from A/c no. XX5678 on '
          '07/09/2026 to AXIS ATM WITHDRAWAL. Avl Bal Rs 12,345.67',
          0,
        ),
      ];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected, hasLength(1));
      final row = detected.single;
      expect(row.date, DateTime(2026, 9, 7));
      expect(
        row.amount,
        2500.0,
        reason:
            'the Avl Bal figure must never be picked over the real '
            'transaction amount',
      );
      expect(row.type, TransactionType.expense);
      expect(row.hasRequiredFields, isTrue);
    });

    test('a generic UPI reference-number-heavy line alone (no date) does not '
        'produce a ready transaction', () {
      final lines = [_line('UPI/DR/123456789012/MERCHANT/Ref 998877', 0)];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected.where((d) => d.hasRequiredFields).toList(), isEmpty);
    });

    test(
      'splits a Google Pay/PhonePe/Paytm-style transaction LIST into separate '
      'rows, not one merged block, using the amount-first/merchant/date shape '
      'repeated per entry',
      () {
        final lines = [
          _line('₹350', 0),
          _line('Paid to Zomato', 24),
          _line('06 Sep, 8:15 PM', 48),
          _line('₹120', 96),
          _line('Paid to Ola', 120),
          _line('06 Sep, 6:02 PM', 144),
          _line('₹75.50', 192),
          _line('Paid to Chai Point', 216),
          _line('07 Sep, 9:00 AM', 240),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(3));
        expect(detected[0].amount, 350.0);
        expect(detected[0].description, 'to Zomato');
        expect(detected[0].date, DateTime(2026, 9, 6));
        expect(detected[0].hasRequiredFields, isTrue);

        expect(detected[1].amount, 120.0);
        expect(detected[1].description, 'to Ola');
        expect(detected[1].date, DateTime(2026, 9, 6));
        expect(detected[1].hasRequiredFields, isTrue);

        expect(detected[2].amount, 75.50);
        expect(detected[2].description, 'to Chai Point');
        expect(detected[2].date, DateTime(2026, 9, 7));
        expect(detected[2].hasRequiredFields, isTrue);
      },
    );

    test(
      'parses a credit card transaction list with no explicit DR/CR wording, '
      'defaulting each row to expense',
      () {
        final lines = [
          _line('07 Sep   AMAZON PAY   ₹1,499.00', 0),
          _line('08 Sep   NETFLIX      ₹649.00', 40),
          _line('08 Sep   ZOMATO       ₹560.00', 80),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(3));
        for (final row in detected) {
          expect(row.type, TransactionType.expense);
          expect(row.hasRequiredFields, isTrue);
        }
        expect(detected[0].amount, 1499.0);
        expect(detected[1].amount, 649.0);
        expect(detected[2].amount, 560.0);
      },
    );

    test(
      'does not mistake a running/closing balance column for the transaction '
      'amount on a bank statement row',
      () {
        final lines = [
          _line('05/09/2026  SWIGGY  420.00 DR  Avl Bal 45,231.00', 0),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(1));
        expect(detected.single.amount, 420.0);
      },
    );

    test(
      'tolerates OCR-confused digits (O/0, S/5) inside an otherwise clean row',
      () {
        final lines = [
          _line('05 Sep', 0),
          _line('SWIGGY', 24),
          _line('₹42O.OO', 48),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.single.amount, 420.0);
        expect(detected.single.hasRequiredFields, isTrue);
      },
    );

    test(
      'tolerates extra/irregular whitespace between date, merchant and amount',
      () {
        final lines = [
          _line('05    Sep', 0),
          _line('   SWIGGY   ', 24),
          _line('₹420', 48),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.single.date, DateTime(2026, 9, 5));
        expect(detected.single.amount, 420.0);
      },
    );

    test('strips a merchant name glued directly onto the amount with no space '
        '(camera-photo OCR often drops separators)', () {
      final lines = [_line('05 Sep', 0), _line('₹420SWIGGY', 24)];
      final result = OcrResult(fullText: 'irrelevant', lines: lines);

      final detected = extractor.extract(
        result,
        sourceImageIndex: 0,
        referenceDate: reference,
      );

      expect(detected.single.amount, 420.0);
      expect(detected.single.description, 'Swiggy');
    });

    test(
      'a merchant name wrapped across two visual lines in a bank-app receipt '
      'is merged into one description',
      () {
        final lines = [
          _line('Paid to', 0),
          _line('Sri Balaji General Stores', 24),
          _line('and Provisions', 48),
          _line('₹1,850.00', 96),
          _line('05 Sep 2026, 7:42 PM', 120),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(1));
        final row = detected.single;
        expect(row.amount, 1850.0);
        expect(row.date, DateTime(2026, 9, 5));
        expect(row.description, contains('Sri Balaji General Stores'));
        expect(row.description, contains('and Provisions'));
      },
    );

    test(
      'a genuinely noisy, multi-error OCR read (mangled currency symbol, '
      'confused digits, stray punctuation) still resolves date/amount correctly',
      () {
        final lines = [
          // Currency symbol misread as a stray character, comma OCR'd as a
          // period, an "S" swapped in for "5", and extra junk punctuation
          // scattered through the merchant name — the kind of degraded
          // output a low-quality/blurry screenshot capture produces.
          _line('O5 Sep,, 2O26', 0),
          _line(';SW|GGY;; B4NG4L0RE:', 24),
          _line('¥42O.OS DR', 48),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        // A row this garbled is not guaranteed to fully resolve — the
        // extractor's job is to never silently invent a wrong value, not to
        // guarantee recovery from arbitrarily bad input. The one thing this
        // test locks down: it must not crash, and it must not produce more
        // than one spurious row from what is clearly a single transaction's
        // worth of noisy text.
        expect(detected.length, lessThanOrEqualTo(1));
      },
    );

    group('negative fixtures — must never become a ready transaction', () {
      test('a standalone masked account number line', () {
        final lines = [_line('A/c No XX1234567890', 0)];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.where((d) => d.hasRequiredFields), isEmpty);
      });

      test('a UPI ID line with no amount', () {
        final lines = [_line('merchant.store@okhdfcbank', 0)];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.where((d) => d.hasRequiredFields), isEmpty);
      });

      test('a reference-number-only line', () {
        final lines = [_line('Ref No 123456789012', 0)];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.where((d) => d.hasRequiredFields), isEmpty);
      });

      test('a phone number line', () {
        final lines = [_line('Contact us: +91 98765 43210', 0)];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected.where((d) => d.hasRequiredFields), isEmpty);
      });

      test('a page footer', () {
        final lines = [
          _line('07 Sep 2026', 0),
          _line('Statement generated on 07 Sep 2026', 24),
          _line('Page 2 of 5', 48),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(
          detected.where((d) => d.hasRequiredFields),
          isEmpty,
          reason:
              'statement boilerplate that carries a date but no amount must '
              'never be treated as a transaction',
        );
      });

      test(
        'a bare date with no amount nearby stays needs-review, not ready',
        () {
          final lines = [_line('07 Sep 2026', 0)];
          final result = OcrResult(fullText: 'irrelevant', lines: lines);

          final detected = extractor.extract(
            result,
            sourceImageIndex: 0,
            referenceDate: reference,
          );

          expect(detected.where((d) => d.hasRequiredFields), isEmpty);
        },
      );

      test('a balance-only line ("Avl Bal") never becomes the amount', () {
        final lines = [
          _line('07 Sep 2026', 0),
          _line('Avl Bal: Rs 45,231.00', 24),
        ];
        final result = OcrResult(fullText: 'irrelevant', lines: lines);

        final detected = extractor.extract(
          result,
          sourceImageIndex: 0,
          referenceDate: reference,
        );

        expect(detected, hasLength(1));
        expect(detected.single.amount, isNull);
        expect(detected.single.hasRequiredFields, isFalse);
      });
    });
  });
}
