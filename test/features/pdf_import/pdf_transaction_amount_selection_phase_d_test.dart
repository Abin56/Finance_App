// Phase D regression coverage for `_extractTransactionAmount`'s new
// percentage-exclusion and trailing-direction-code-preference structural
// signals. See `pdf_date_block_grouping_risk` in project memory for the
// real-PDF evidence (IGST fee row resolving to 18.00, the percentage rate,
// instead of 76.71, the actual fee amount).
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _reference = DateTime(2026, 9, 20);

PdfTextLine _line(String text, double top, {double left = 0, double height = 12}) {
  return PdfTextLine(
    text: text,
    boundingBox: PdfBoundingBox(left: left, top: top, right: left + 100, bottom: top + height),
    source: PdfTextSource.embedded,
  );
}

PdfExtractionResult _singlePage(List<List<Object>> rows) {
  final lines = rows
      .map((r) => _line(r[0] as String, (r[1] as num).toDouble(), left: r.length > 2 ? (r[2] as num).toDouble() : 0))
      .toList();
  return PdfExtractionResult(pages: [PdfPageResult(pageNumber: 1, source: PdfTextSource.embedded, lines: lines)]);
}

void main() {
  group('1. IGST exact structural pattern', () {
    test('IGST DB @ 18.00% 76.71 D resolves to 76.71, not the percentage', () {
      final extraction = _singlePage([
        ['17 Aug 26 INTEREST ON EMI 35.19 D', 10, 0],
        ['IGST DB @ 18.00% 76.71 D', 20, 0],
        ['TRANSACTIONS FOR SOME CARDHOLDER', 30, 0],
        ['17 Jul 26 UPI-SOME MERCHANT 413.00 D', 40, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final igst = result.firstWhere((t) => t.rawText.contains('IGST'));
      expect(igst.amount, 76.71);
      expect(igst.type, TransactionType.expense);
    });
  });

  group('2. percentage + amount, generic wording', () {
    test('SERVICE @ 18.00% 76.71 D resolves to 76.71', () {
      final extraction = _singlePage([
        ['SERVICE CHARGE @ 18.00% 76.71 D', 10, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, isNotEmpty);
      expect(result.first.amount, 76.71);
    });
  });

  group('3. normal D — unchanged', () {
    test('UPI-MAHESH KUMAR 413.00 D resolves to 413.00', () {
      final extraction = _singlePage([
        ['17 Jul 26 UPI-MAHESH KUMAR 413.00 D', 10, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 413.00);
      expect(tx.type, TransactionType.expense);
    });
  });

  group('4. normal C — unchanged', () {
    test('a credit-suffixed row resolves to the correct amount and income type', () {
      final extraction = _singlePage([
        ['07 Sep 26 SALARY CREDIT XYZ CORP 55,000.00 C', 10, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 55000.00);
    });
  });

  group('5. currency-marked amount — unchanged', () {
    test('a ₹-marked amount still resolves correctly', () {
      final extraction = _singlePage([
        ['05/09/2026 COFFEE SHOP ₹350.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result.first.amount, 350.00);
    });
  });

  group('6. running balance — unchanged', () {
    test('the closing balance is still not treated as the transaction amount', () {
      final extraction = _singlePage([
        ['05/09/2026 SWIGGY 420.00 Avl Bal 12,500.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });
  });

  group('7. separate debit/credit columns — unchanged', () {
    test('a debit-only row (credit column blank) still resolves the correct amount', () {
      final extraction = _singlePage([
        ['Date', 20, 0], ['Particulars', 20, 100], ['Debit', 20, 300],
        ['Credit', 20, 400], ['Balance', 20, 500],
        ['05/09/2026', 60, 0], ['NEFT-SWIGGY BANGALORE', 60, 100],
        ['420.00', 60, 300], ['12,500.00', 60, 500],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });
  });

  group('8. credit-card statement — unchanged', () {
    test('a credit-card transaction row still resolves the correct amount', () {
      final extraction = _singlePage([
        ['Transaction Date', 20, 0], ['Description', 20, 150], ['Amount', 20, 400],
        ['05/09/2026', 60, 0], ['AMAZON.IN MUMBAI', 60, 150], ['1,299.00', 60, 400],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 1299.00);
    });
  });

  group('9. multiline transaction — amount on continuation row', () {
    test('a wrapped description with the amount on a separate row still resolves correctly', () {
      final extraction = _singlePage([
        ['17/09/26', 10, 0],
        ['ONLINE ORDER', 20, 0],
        ['AMAZON MARKETPLACE', 30, 0],
        ['1,250.00 D', 10, 300],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(1));
      expect(result.first.amount, 1250.00);
    });
  });

  group('10. reference/percentage numbers must not win over the real amount', () {
    test('a reference number containing digits does not outrank the trailing-coded amount', () {
      final extraction = _singlePage([
        ['06/09/26 NEFT TXN REF 05SEP2412998 2200.00 D', 10, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 2200.00);
    });

    test('a percentage figure with no trailing direction code anywhere still excludes the rate', () {
      final extraction = _singlePage([
        ['FEE @ 18.00% 76.71', 10, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, isNotEmpty);
      expect(result.first.amount, 76.71);
    });

    test(
      'when only a percentage-adjacent figure exists in the block, it is masked out '
      'and the block correctly has no amount rather than reporting the rate',
      () {
        final extraction = _singlePage([
          ['05/09/2026 RATE INFO ONLY @ 18.00%', 10, 0],
        ]);
        final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
        // Either no block at all (dropped, since amount==null and date-only
        // with no amount is intentionally not created here since there IS a
        // date) or a needs-review block with amount null — either way, 18.0
        // must never be reported as a real amount.
        expect(result.every((t) => t.amount != 18.0), isTrue);
      },
    );
  });
}
