import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_layout_reconstructor.dart';
import 'package:flutter_test/flutter_test.dart';

PdfTextLine _line(String text, double top, {double left = 0, double height = 12}) {
  return PdfTextLine(
    text: text,
    boundingBox: PdfBoundingBox(
      left: left,
      top: top,
      right: left + 100,
      bottom: top + height,
    ),
    source: PdfTextSource.embedded,
  );
}

void main() {
  const reconstructor = PdfLayoutReconstructor();

  group('PdfLayoutReconstructor row reconstruction', () {
    test('merges lines at the same vertical position into one row, left-to-right', () {
      final page = PdfPageResult(
        pageNumber: 1,
        source: PdfTextSource.embedded,
        lines: [
          _line('SWIGGY BANGALORE', 100, left: 150),
          _line('05/09/2026', 100, left: 0),
          _line('420.00', 100, left: 400),
        ],
      );
      final rows = reconstructor.reconstructRows(
        PdfExtractionResult(pages: [page]),
      );
      expect(rows, hasLength(1));
      expect(rows.first.text, '05/09/2026  SWIGGY BANGALORE  420.00');
      expect(rows.first.columnTexts, [
        '05/09/2026',
        'SWIGGY BANGALORE',
        '420.00',
      ]);
    });

    test('keeps rows at different vertical positions separate', () {
      final page = PdfPageResult(
        pageNumber: 1,
        source: PdfTextSource.embedded,
        lines: [_line('Row A', 100), _line('Row B', 140)],
      );
      final rows = reconstructor.reconstructRows(
        PdfExtractionResult(pages: [page]),
      );
      expect(rows, hasLength(2));
    });

    test('strips a header/footer line repeated across a majority of pages', () {
      final pages = List.generate(3, (i) {
        return PdfPageResult(
          pageNumber: i + 1,
          source: PdfTextSource.embedded,
          lines: [
            _line('ABC Bank Statement of Account', 20),
            _line('0${i + 5}/09/2026 SWIGGY 420.00', 100),
            _line('Generated on 07 Sep 2026', 700),
          ],
        );
      });
      final rows = reconstructor.reconstructRows(
        PdfExtractionResult(pages: pages),
      );
      expect(
        rows.any((r) => r.text.contains('Statement of Account')),
        isFalse,
      );
      expect(rows.any((r) => r.text.contains('Generated on')), isFalse);
      expect(rows.where((r) => r.text.contains('SWIGGY')), hasLength(3));
    });

    test('does not strip anything on a single-page statement', () {
      final page = PdfPageResult(
        pageNumber: 1,
        source: PdfTextSource.embedded,
        lines: [
          _line('ABC Bank Statement of Account', 20),
          _line('05/09/2026 SWIGGY 420.00', 100),
        ],
      );
      final rows = reconstructor.reconstructRows(
        PdfExtractionResult(pages: [page]),
      );
      expect(rows, hasLength(2));
    });

    test('preserves page numbers across a multi-page document', () {
      final pages = [
        PdfPageResult(
          pageNumber: 1,
          source: PdfTextSource.embedded,
          lines: [_line('05/09/2026 SWIGGY 420.00', 100)],
        ),
        PdfPageResult(
          pageNumber: 2,
          source: PdfTextSource.embedded,
          lines: [_line('06/09/2026 ZOMATO 250.00', 100)],
        ),
      ];
      final rows = reconstructor.reconstructRows(
        PdfExtractionResult(pages: pages),
      );
      expect(rows.map((r) => r.pageNumber), [1, 2]);
    });
  });
}
