import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_layout_reconstructor.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/smart_import/domain/screenshot_duplicate_detector.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _reference = DateTime(2026, 9, 7);

PdfTextLine _ocrLine(String text, double top, {double left = 0}) {
  return PdfTextLine(
    text: text,
    boundingBox: PdfBoundingBox(
      left: left,
      top: top,
      right: left + 200,
      bottom: top + 12,
    ),
    source: PdfTextSource.ocr,
  );
}

/// Verifies the exact same [PdfLayoutReconstructor] → [PdfTransactionParser]
/// pipeline the embedded-text path already uses (see
/// pdf_transaction_parser_test.dart / pdf_layout_reconstructor_test.dart)
/// also correctly handles [PdfTextSource.ocr]-tagged input — proving there
/// is no second parser and no OCR-specific branching anywhere in the
/// layout/parsing stages. Every fixture here is a synthetic OCR-style
/// result (deliberately including the kind of misreads a real OCR engine
/// produces — confusable digits, altered casing) rather than real recognizer
/// output, since ML Kit itself is faked out at the controller/service layer
/// (see pdf_ocr_fallback_controller_test.dart) and never exercised in unit
/// tests.
void main() {
  group('OCR-sourced PdfExtractionResult — Fixture A: single-page scanned bank statement', () {
    test('parses a simple single-page scanned statement end to end', () {
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [
              _ocrLine('ABC Bank Statement of Account', 10),
              _ocrLine('05/09/2026 SWIGGY BANGALORE 420.00', 100),
              _ocrLine('06/09/2026 UBER TRIP 185.50', 130),
            ],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, hasLength(2));
      expect(result[0].amount, 420.0);
      expect(result[1].amount, 185.50);
    });
  });

  group('OCR-sourced PdfExtractionResult — Fixture B: multi-page scanned statement', () {
    test('merges transactions across scanned pages, preserving page order', () {
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [_ocrLine('05/09/2026 SWIGGY 420.00', 100)],
          ),
          PdfPageResult(
            pageNumber: 2,
            source: PdfTextSource.ocr,
            lines: [_ocrLine('06/09/2026 UBER 185.50', 100)],
          ),
          PdfPageResult(
            pageNumber: 3,
            source: PdfTextSource.ocr,
            lines: [_ocrLine('07/09/2026 AMAZON 1,299.00', 100)],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, hasLength(3));
      expect(result[0].date, DateTime(2026, 9, 5));
      expect(result[1].date, DateTime(2026, 9, 6));
      expect(result[2].date, DateTime(2026, 9, 7));
    });
  });

  group('OCR-sourced PdfExtractionResult — Fixture C: scanned credit-card statement', () {
    test('parses a scanned credit-card statement layout (Transaction Date/Description/Amount)', () {
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [
              _ocrLine('Transaction Date', 20),
              _ocrLine('Description', 20, left: 150),
              _ocrLine('Amount', 20, left: 400),
              _ocrLine('05/09/2026', 60),
              _ocrLine('AMAZON.IN MUMBAI', 60, left: 150),
              _ocrLine('1,299.00', 60, left: 400),
            ],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 1299.0);
      expect(tx.description.toUpperCase(), contains('AMAZON'));
    });
  });

  group('OCR-sourced PdfExtractionResult — Fixture D: poor-but-readable scan', () {
    test('handles common OCR digit/letter confusions without silently inventing a wrong value', () {
      // "₹420.00" misread as "₹42O.OO" (O for 0) — the amount parser's
      // OCR-confusable character class already handles this; this test
      // verifies that behavior survives the full PDF pipeline, not just
      // SmartImportAmountParser in isolation.
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [_ocrLine('05/09/2026 SWIGGV BANGALORE ₹42O.OO', 100)],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, hasLength(1));
      expect(
        result.single.amount,
        420.0,
        reason: 'OCR-confusable O/0 in the amount must still resolve correctly',
      );
      expect(result.single.date, DateTime(2026, 9, 5));
    });

    test('a genuinely unresolvable OCR date is left for review rather than guessed', () {
      // "05 Sep" garbled beyond what the date parser can recover ("O5
      // 5ep") — must not silently attach a wrong date; the row still
      // surfaces (it has an amount) but without a date, correctly needing
      // review.
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [_ocrLine('O5 5ep SWIGGY BANGALORE ₹420.00', 100)],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, hasLength(1));
      final tx = result.single;
      expect(tx.date, isNull);
      expect(tx.reviewStatus, DetectionReviewStatus.needsReview);
      expect(
        tx.isSelected,
        isFalse,
        reason: 'an unresolvable date must not be silently invented, and the row must not be pre-selected',
      );
    });
  });

  group('OCR-sourced PdfExtractionResult — Fixture E: repeated headers/footers', () {
    test('strips a header/footer OCR-read identically on every scanned page', () {
      final pages = List.generate(3, (i) {
        return PdfPageResult(
          pageNumber: i + 1,
          source: PdfTextSource.ocr,
          lines: [
            _ocrLine('ABC Bank Statement of Account', 10),
            _ocrLine('0${i + 5}/09/2026 MERCHANT ${i + 1} ${(i + 1) * 100}.00', 100),
            _ocrLine('Generated on 07 Sep 2026', 700),
          ],
        );
      });

      final result = PdfTransactionParser.extract(
        PdfExtractionResult(pages: pages),
        referenceDate: _reference,
      );

      expect(result, hasLength(3));
      expect(
        result.any((t) => t.rawText.toLowerCase().contains('statement of account')),
        isFalse,
        reason: 'a repeated header OCR-read the same on every page must never surface as a transaction',
      );
      expect(
        result.any((t) => t.rawText.toLowerCase().contains('generated on')),
        isFalse,
        reason: 'a repeated footer must never surface as a transaction',
      );
    });

    test('does not strip anything from a single scanned page', () {
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [
              _ocrLine('ABC Bank Statement of Account', 10),
              _ocrLine('05/09/2026 SWIGGY 420.00', 100),
            ],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, hasLength(1));
    });
  });

  group('OCR-sourced PdfExtractionResult — Fixture F: date/merchant/debit/credit/amount/balance', () {
    test('separates the running balance from the transaction amount on a scanned row', () {
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [
              _ocrLine('05/09/2026 SWIGGY BANGALORE 420.00 Avl Bal 12,500.00', 100),
            ],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final tx = result.firstWhere((t) => t.amount != null);
      expect(
        tx.amount,
        420.0,
        reason: 'the running balance (12,500.00) must never be picked as the transaction amount',
      );
    });

    test('debit and credit rows on scanned pages resolve to the correct transaction type', () {
      final extraction = PdfExtractionResult(
        pages: [
          PdfPageResult(
            pageNumber: 1,
            source: PdfTextSource.ocr,
            lines: [
              _ocrLine('05/09/2026 ATM WDL 2,000.00 DR', 100),
              _ocrLine('06/09/2026 SALARY CREDIT 50,000.00 CR', 130),
            ],
          ),
        ],
      );

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final debit = result.firstWhere((t) => t.amount == 2000.0);
      final credit = result.firstWhere((t) => t.amount == 50000.0);
      expect(debit.type, TransactionType.expense);
      expect(credit.type, TransactionType.income);
    });
  });

  group('OCR-sourced PdfExtractionResult — duplicate detection', () {
    test(
      'a scanned transaction matching an already-imported one is flagged as a possible duplicate',
      () {
        final extraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.ocr,
              lines: [
                _ocrLine('05/09/2026 SWIGGY BANGALORE 420.00', 100),
                _ocrLine('06/09/2026 UBER 185.50', 130),
              ],
            ),
          ],
        );
        final result = PdfTransactionParser.extract(
          extraction,
          referenceDate: _reference,
        );
        expect(result, hasLength(2));

        final existing = [
          Transaction(
            id: 'existing-1',
            type: TransactionType.expense,
            amount: 420.0,
            dateTime: DateTime(2026, 9, 5),
            accountId: 'acc-1',
            categoryId: 'cat-1',
            description: 'Swiggy',
            createdAt: DateTime(2026, 9, 5),
          ),
        ];
        ScreenshotDuplicateDetector.apply(
          result,
          existing,
          accountId: 'acc-1',
        );

        final swiggy = result.firstWhere((t) => t.amount == 420.0);
        final uber = result.firstWhere((t) => t.amount == 185.50);
        expect(swiggy.isDuplicate, isTrue);
        expect(
          swiggy.isSelected,
          isFalse,
          reason: 'a freshly-flagged duplicate must not be pre-selected for import',
        );
        expect(uber.isDuplicate, isFalse);
      },
    );
  });
}
