// Phase B regression coverage for `PdfTransactionRegionDetector`. Tests the
// detector both directly (unit-level, on reconstructed rows) and through
// `PdfTransactionParser.extract` (integration-level), per the 8 cases
// specified for this phase. No PII from the real validated PDF appears
// here — fixtures use synthetic text modeled on its structural shape only.
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_layout_reconstructor.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_region_detector.dart';
import 'package:flutter_test/flutter_test.dart';

final _reference = DateTime(2026, 9, 20);

PdfTextLine _line(String text, double top, {double left = 0, double height = 12}) {
  return PdfTextLine(
    text: text,
    boundingBox: PdfBoundingBox(left: left, top: top, right: left + 100, bottom: top + height),
    source: PdfTextSource.embedded,
  );
}

PdfPageResult _page(int pageNumber, List<List<Object>> rows) {
  final lines = rows
      .map((r) => _line(r[0] as String, (r[1] as num).toDouble(), left: r.length > 2 ? (r[2] as num).toDouble() : 0))
      .toList();
  return PdfPageResult(pageNumber: pageNumber, source: PdfTextSource.embedded, lines: lines);
}

List<PdfStatementRow> _reconstruct(List<PdfPageResult> pages) {
  const reconstructor = PdfLayoutReconstructor();
  return reconstructor.reconstructRows(PdfExtractionResult(pages: pages));
}

void main() {
  group('1. real-shaped credit-card statement page', () {
    test('transaction region starts at the table header; account-summary rows above it are excluded', () {
      final rows = _reconstruct([
        _page(1, [
          ['GSTIN of Card : [REDACTED]  Statement/Tax Invoice', 10, 0],
          ['CARDHOLDER NAME  Credit Card Number', 20, 0],
          ['XXXX XXXX XXXX XX00', 30, 0],
          ['Total Amount Due', 40, 0],
          ['34,300.00  incl. EMI', 50, 0],
          ['Available Credit Limit Payment Due Date', 60, 0],
          ['20,668.83  06 Sep 2026', 70, 0],
          ['ACCOUNT SUMMARY', 80, 0],
          ['Previous Balance Total Outstanding Payments Credits', 90, 0],
          ['68,462.99  41,208.00 31,573.26', 100, 0],
          ['Date Amount  Transaction Details', 110, 0],
          ['for Statement Period: 18 Jul 26 to 17 Aug 26', 115, 0],
          ['31 Jul 26 PAYMENT RECEIVED REF12345 41,208.00 C', 120, 0],
          ['17 Aug 26 SOME MERCHANT PAYMENT 391.02 D', 130, 0],
          ['17 Aug 26 ANOTHER MERCHANT 35.19 D', 140, 0],
        ]),
      ]);

      final region = PdfTransactionRegionDetector.detect(rows, referenceDate: _reference);
      expect(region, isNotNull);
      final regionTexts = region!.map((r) => r.text).toList();
      expect(regionTexts.any((t) => t.contains('34,300.00')), isFalse,
          reason: 'summary figure before the header must be excluded');
      expect(regionTexts.any((t) => t.contains('PAYMENT RECEIVED')), isTrue);
      expect(regionTexts.any((t) => t.contains('ANOTHER MERCHANT')), isTrue);
    });
  });

  group('2. same-page trailing boilerplate', () {
    test('final real transaction is retained; following legal text is excluded', () {
      final rows = _reconstruct([
        _page(1, [
          ['Date Amount  Transaction Details', 10, 0],
          ['01 Sep 26 MERCHANT ONE 100.00 D', 20, 0],
          ['02 Sep 26 MERCHANT TWO 200.00 D', 30, 0],
          ['03 Sep 26 MERCHANT THREE 300.00 D', 40, 0],
          ['04 Sep 26 FINAL MERCHANT 285.00 D', 50, 0],
          ['Transactions highlighted in grey color do not form part of Purchases', 60, 0],
          ['C=Credit ; D=Debit; EN=Encash; FP=Flexipay', 70, 0],
          ['Important Messages', 80, 0],
          ['Total Amount Due needs to be paid by payment due date to avoid levy', 90, 0],
          ['of finance charges on new transactions done after the statement date', 100, 0],
          ['Rs.100 for Outstanding Amount Due greater than Rs.100 up to Rs.500', 110, 0],
        ]),
      ]);

      final region = PdfTransactionRegionDetector.detect(rows, referenceDate: _reference);
      expect(region, isNotNull);
      final regionTexts = region!.map((r) => r.text).toList();
      expect(regionTexts.any((t) => t.contains('FINAL MERCHANT')), isTrue,
          reason: 'the last real transaction must be retained');
      expect(regionTexts.any((t) => t.contains('Rs.100')), isFalse,
          reason: 'trailing legal/fee-schedule prose must be excluded');
      expect(regionTexts.any((t) => t.contains('C=Credit')), isFalse);
    });

    test(
      'end-to-end: trailing boilerplate does not corrupt the final transaction\'s amount/direction',
      () {
        final extraction = PdfExtractionResult(pages: [
          _page(1, [
            ['Date Amount  Transaction Details', 10, 0],
            ['01 Sep 26 MERCHANT ONE 100.00 D', 20, 0],
            ['02 Sep 26 FINAL MERCHANT CATERING 285.00 D', 30, 0],
            ['Transactions highlighted in grey color do not form part of Purchases', 40, 0],
            ['C=Credit ; D=Debit', 50, 0],
            ['Rs.100 for Outstanding Amount Due greater than Rs.100 up to Rs.500', 60, 0],
          ]),
        ]);
        final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
        final finalTx = result.firstWhere((t) => t.description.contains('FINAL MERCHANT'));
        expect(finalTx.amount, 285.00);
      },
    );
  });

  group('3. multi-page statement', () {
    test('transaction regions are detected independently on each page', () {
      final rows = _reconstruct([
        _page(1, [
          ['Date Amount  Transaction Details', 10, 0],
          ['01 Sep 26 MERCHANT ONE 100.00 D', 20, 0],
          ['02 Sep 26 MERCHANT TWO 200.00 D', 30, 0],
          ['03 Sep 26 MERCHANT THREE 300.00 D', 40, 0],
        ]),
        _page(2, [
          ['Transaction Details', 10, 0],
          ['Date  for Statement Period  Amount', 20, 0],
          ['04 Sep 26 MERCHANT FOUR 400.00 D', 30, 0],
          ['05 Sep 26 MERCHANT FIVE 500.00 D', 40, 0],
        ]),
      ]);

      final region = PdfTransactionRegionDetector.detect(rows, referenceDate: _reference);
      expect(region, isNotNull);
      expect(region!.any((r) => r.text.contains('MERCHANT ONE')), isTrue);
      expect(region.any((r) => r.text.contains('MERCHANT FOUR')), isTrue);
      expect(region.any((r) => r.text.contains('MERCHANT FIVE')), isTrue);
    });
  });

  group('4. unrelated table page', () {
    test('a fee-schedule/legal-only page is entirely excluded', () {
      final rows = _reconstruct([
        _page(1, [
          ['Date Amount  Transaction Details', 10, 0],
          ['01 Sep 26 MERCHANT ONE 100.00 D', 20, 0],
          ['02 Sep 26 MERCHANT TWO 200.00 D', 30, 0],
        ]),
        _page(2, [
          ['Schedule of Charges', 10, 0],
          ['Annual Card Name Fee Renewal Fee', 20, 0],
          ['9,999 Waived off on annual spends of 12 Lakh or more', 30, 0],
          ['AURUM 9,999 in the preceding year', 40, 0],
          ['KrisFlyer Card Apex 9,999 9,999', 50, 0],
          ['effect from transactions dated 17-Nov-2011.', 60, 0],
        ]),
      ]);

      final region = PdfTransactionRegionDetector.detect(rows, referenceDate: _reference);
      expect(region, isNotNull);
      expect(region!.any((r) => r.pageNumber == 2), isFalse,
          reason: 'a page with no transaction-shaped rows must contribute nothing to the region');
    });
  });

  group('5. headerless receipt-style PDF — fallback', () {
    test('no region detected; PdfTransactionParser.extract behavior is unchanged', () {
      final extraction = PdfExtractionResult(pages: [
        _page(1, [
          ['AMAZON PAY - ONLINE PURCHASE', 20, 0],
          ['₹1,299.00', 60, 0],
          ['05 Sep 2026', 100, 0],
        ]),
      ]);
      final rows = _reconstruct(extraction.pages);
      final region = PdfTransactionRegionDetector.detect(rows, referenceDate: _reference);
      expect(region, isNull, reason: 'too sparse/headerless to confidently detect a region');

      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(1));
      expect(result.first.amount, 1299.00);
      expect(result.first.date, DateTime(2026, 9, 5));
    });
  });

  group('6. date-last PDF — fallback remains functional', () {
    test('a small date-last statement with no header still parses via fallback', () {
      final extraction = PdfExtractionResult(pages: [
        _page(1, [
          ['UBER TRIP FARE', 20, 0],
          ['235.00', 40, 0],
          ['06 Sep 2026', 60, 0],
        ]),
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(1));
      expect(result.first.amount, 235.00);
      expect(result.first.date, DateTime(2026, 9, 6));
    });
  });

  group('7. existing bank-style fixtures — no transactions disappear', () {
    test('HDFC-style single-line table with running balance still parses', () {
      final extraction = PdfExtractionResult(pages: [
        _page(1, [
          ['Date', 20, 0],
          ['Narration', 20, 100],
          ['Withdrawal Amt.', 20, 250],
          ['Deposit Amt.', 20, 350],
          ['Closing Balance', 20, 450],
          ['05/09/26 UPI-SWIGGY BANGALORE-420.00', 60, 0],
          ['12,500.00', 60, 450],
        ]),
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, isNotEmpty);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.date, DateTime(2026, 9, 5));
    });

    test('SBI-style DR-suffixed row still parses', () {
      final extraction = PdfExtractionResult(pages: [
        _page(1, [
          ['06-Sep-2026', 30, 0],
          ['ATM WDL NEFT REF1234567', 30, 100],
          ['5,000.00 DR', 30, 350],
          ['45,200.00', 30, 450],
        ]),
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 5000.00);
    });

    test('ICICI/Axis-style separate Debit/Credit columns still parses', () {
      final extraction = PdfExtractionResult(pages: [
        _page(1, [
          ['Date', 20, 0],
          ['Particulars', 20, 100],
          ['Debit', 20, 300],
          ['Credit', 20, 400],
          ['Balance', 20, 500],
          ['05/09/2026', 60, 0],
          ['NEFT-SWIGGY BANGALORE', 60, 100],
          ['420.00', 60, 300],
          ['12,500.00', 60, 500],
        ]),
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });

    test('credit-card statement layout still parses', () {
      final extraction = PdfExtractionResult(pages: [
        _page(1, [
          ['Transaction Date', 20, 0],
          ['Description', 20, 150],
          ['Amount', 20, 400],
          ['05/09/2026', 60, 0],
          ['AMAZON.IN MUMBAI', 60, 150],
          ['1,299.00', 60, 400],
        ]),
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 1299.00);
    });
  });

  group('8. dense multiline transaction fixture', () {
    test('a wrapped description continuation row is not treated as an end-of-region boundary', () {
      final extraction = PdfExtractionResult(pages: [
        _page(1, [
          ['Date Amount  Transaction Details', 10, 0],
          ['01 Sep 26 MERCHANT ONE 100.00 D', 20, 0],
          ['02 Sep 26 NEFT TRANSFER TO', 30, 0],
          ['JOHN DOE ACCOUNT SERVICES PRIVATE LIMITED', 40, 0],
          ['420.00', 30, 300],
          ['03 Sep 26 MERCHANT THREE 300.00 D', 50, 0],
        ]),
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(3));
      final wrapped = result.firstWhere((t) => t.description.contains('JOHN DOE'));
      expect(wrapped.description, contains('NEFT TRANSFER'));
      expect(wrapped.amount, 420.00);
      expect(result.any((t) => t.description.contains('MERCHANT THREE')), isTrue);
    });
  });
}
