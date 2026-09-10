import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:flutter_test/flutter_test.dart';

PdfTextLine _line(String text) {
  return PdfTextLine(
    text: text,
    boundingBox: const PdfBoundingBox(left: 0, top: 0, right: 10, bottom: 10),
    source: PdfTextSource.embedded,
  );
}

PdfPageResult _page(int pageNumber, List<String> texts) {
  return PdfPageResult(
    pageNumber: pageNumber,
    lines: [for (final t in texts) _line(t)],
    source: PdfTextSource.embedded,
  );
}

void main() {
  group('PdfExtractionResult.looksLikeScannedDocument', () {
    test('true for a document with no pages at all is false (nothing to classify)', () {
      const result = PdfExtractionResult(pages: []);
      expect(result.looksLikeScannedDocument, isFalse);
    });

    test('true when no page has any text', () {
      final result = PdfExtractionResult(
        pages: [_page(1, []), _page(2, [])],
      );
      expect(result.looksLikeScannedDocument, isTrue);
    });

    test('false for a normal statement page with real content', () {
      final result = PdfExtractionResult(
        pages: [
          _page(1, [
            'ABC Bank Statement of Account',
            'Account Holder: John Doe',
            'Statement Period: 01 Sep 2026 to 30 Sep 2026',
            '05/09/2026 UPI-SWIGGY BANGALORE-420.00',
            '06/09/2026 AMAZON PAY INDIA 1,299.00 DR',
          ]),
        ],
      );
      expect(result.looksLikeScannedDocument, isFalse);
    });

    test(
      'false for a multi-page statement where only one page is sparse (a short addendum)',
      () {
        final result = PdfExtractionResult(
          pages: [
            _page(1, [
              'ABC Bank Statement of Account',
              'Account Holder: John Doe',
              '05/09/2026 UPI-SWIGGY BANGALORE-420.00',
              '06/09/2026 AMAZON PAY INDIA 1,299.00 DR',
              '07/09/2026 SALARY CREDIT XYZ CORP 50,000.00 CR',
            ]),
            _page(2, ['Page 2 of 2']),
          ],
        );
        expect(result.looksLikeScannedDocument, isFalse);
      },
    );

    test(
      'true when embedded text exists but is only a stray watermark/page number on every page',
      () {
        final result = PdfExtractionResult(
          pages: [_page(1, ['1']), _page(2, ['2'])],
        );
        expect(result.looksLikeScannedDocument, isTrue);
      },
    );

    test('true for a single scanned page with a single stray character', () {
      final result = PdfExtractionResult(pages: [_page(1, ['®'])]);
      expect(result.looksLikeScannedDocument, isTrue);
    });
  });
}
