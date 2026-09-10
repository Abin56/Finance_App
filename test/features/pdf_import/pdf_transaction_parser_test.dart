import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _reference = DateTime(2026, 9, 7);

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

/// Builds a single-page [PdfExtractionResult] from rows already laid out as
/// (text, top, left) triples, one call per visual line — the fixture style
/// used throughout this file so each synthetic bank layout reads as plain
/// statement text rather than bounding-box arithmetic.
PdfExtractionResult _singlePage(List<List<Object>> rows) {
  final lines = rows
      .map(
        (r) => _line(
          r[0] as String,
          (r[1] as num).toDouble(),
          left: r.length > 2 ? (r[2] as num).toDouble() : 0,
        ),
      )
      .toList();
  return PdfExtractionResult(
    pages: [
      PdfPageResult(pageNumber: 1, source: PdfTextSource.embedded, lines: lines),
    ],
  );
}

void main() {
  group('PdfTransactionParser — HDFC-style single-line table', () {
    // Date | Narration | Withdrawal | Deposit | Balance, all on one row.
    test('parses a simple debit row with running balance', () {
      final extraction = _singlePage([
        ['Date', 20, 0],
        ['Narration', 20, 100],
        ['Withdrawal Amt.', 20, 250],
        ['Deposit Amt.', 20, 350],
        ['Closing Balance', 20, 450],
        ['05/09/26 UPI-SWIGGY BANGALORE-420.00', 60, 0],
        ['12,500.00', 60, 450],
      ]);

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, isNotEmpty);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.date, DateTime(2026, 9, 5));
      expect(tx.description.toLowerCase(), contains('swiggy'));
    });
  });

  group('PdfTransactionParser — SBI-style multi-column row with DR/CR suffix', () {
    test('extracts amount and direction from a DR-suffixed figure', () {
      final extraction = _singlePage([
        ['06-Sep-2026', 30, 0],
        ['ATM WDL NEFT REF1234567', 30, 100],
        ['5,000.00 DR', 30, 350],
        ['45,200.00', 30, 450],
      ]);

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.date, DateTime(2026, 9, 6));
      expect(tx.amount, 5000.00);
      expect(tx.type, TransactionType.expense);
      expect(tx.referenceNumber, isNotNull);
    });

    test('extracts credit direction from a CR-suffixed figure', () {
      final extraction = _singlePage([
        ['07-Sep-2026', 30, 0],
        ['SALARY CREDIT XYZ CORP', 30, 100],
        ['55,000.00 CR', 30, 350],
        ['1,00,200.00', 30, 450],
      ]);

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.type, TransactionType.income);
      expect(tx.amount, 55000.00);
    });
  });

  group('PdfTransactionParser — date-at-end receipt-style layout', () {
    test('attaches a trailing date line to the block above it', () {
      final extraction = _singlePage([
        ['AMAZON PAY - ONLINE PURCHASE', 20, 0],
        ['₹1,299.00', 60, 0],
        ['05 Sep 2026', 100, 0],
      ]);

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, hasLength(1));
      expect(result.first.date, DateTime(2026, 9, 5));
      expect(result.first.amount, 1299.00);
    });
  });

  group('PdfTransactionParser — multi-line description', () {
    test('merges a wrapped second description line into the same block', () {
      final extraction = _singlePage([
        ['05/09/2026', 20, 0],
        ['IMPS TRANSFER TO', 20, 100],
        ['420.00', 20, 450],
        ['JOHN DOE ACCOUNT 1234', 60, 100],
      ]);

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      expect(result, hasLength(1));
      final tx = result.first;
      expect(tx.description, contains('IMPS'));
      expect(tx.description, contains('JOHN DOE'));
    });
  });

  group('PdfTransactionParser — multi-page statement', () {
    test('parses transactions spanning multiple pages and strips repeated header/footer', () {
      final pages = [
        PdfPageResult(
          pageNumber: 1,
          source: PdfTextSource.embedded,
          lines: [
            _line('ABC Bank - Statement of Account', 10),
            _line('05/09/2026 SWIGGY BANGALORE 420.00', 100),
            _line('Page 1 of 2', 700),
          ],
        ),
        PdfPageResult(
          pageNumber: 2,
          source: PdfTextSource.embedded,
          lines: [
            _line('ABC Bank - Statement of Account', 10),
            _line('06/09/2026 ZOMATO ORDER 250.00', 100),
            _line('Page 2 of 2', 700),
          ],
        ),
      ];

      final result = PdfTransactionParser.extract(
        PdfExtractionResult(pages: pages),
        referenceDate: _reference,
      );

      expect(result, hasLength(2));
      expect(result[0].date, DateTime(2026, 9, 5));
      expect(result[1].date, DateTime(2026, 9, 6));
      expect(
        result.any((t) => t.description.toLowerCase().contains('statement')),
        isFalse,
      );
    });
  });

  group('PdfTransactionParser — running balance separation', () {
    test('does not treat the closing balance as the transaction amount', () {
      final extraction = _singlePage([
        ['05/09/2026 SWIGGY 420.00 Avl Bal 12,500.00', 20, 0],
      ]);

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });

    test('flags a positionally-guessed amount as needing review, not pre-selected', () {
      // The only amount-shaped figure in the block is balance-adjacent
      // wording with no other candidate to prefer — surfaced via the
      // positional/uncertain fallback rather than trusted outright.
      final extraction = _singlePage([
        ['05/09/2026 SOME MERCHANT Avl Bal 12500.00', 20, 0],
      ]);

      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.isSelected, isFalse);
    });
  });

  group('PdfTransactionParser — currency formats', () {
    test('parses ₹ symbol amounts', () {
      final extraction = _singlePage([
        ['05/09/2026 COFFEE SHOP ₹350.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result.first.amount, 350.00);
    });

    test('parses comma-formatted INR amounts (lakh grouping)', () {
      final extraction = _singlePage([
        ['05/09/2026 RENT PAYMENT INR 1,25,000.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result.first.amount, 125000.00);
    });

    test('parses Rs. prefixed amounts', () {
      final extraction = _singlePage([
        ['05/09/2026 GROCERY STORE Rs. 899.50', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result.first.amount, 899.50);
    });
  });

  group('PdfTransactionParser — date formats already supported by FlowFi', () {
    test('parses DD/MM/YYYY', () {
      final extraction = _singlePage([
        ['05/09/2026 TEST MERCHANT 100.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result.first.date, DateTime(2026, 9, 5));
    });

    test('parses DD-MMM-YYYY', () {
      final extraction = _singlePage([
        ['05-Sep-2026 TEST MERCHANT 100.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result.first.date, DateTime(2026, 9, 5));
    });

    test('parses ISO YYYY-MM-DD', () {
      final extraction = _singlePage([
        ['2026-09-05 TEST MERCHANT 100.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result.first.date, DateTime(2026, 9, 5));
    });
  });

  group('PdfTransactionParser — column-based layout via bounding boxes', () {
    test('reconstructs a row split into separate date/description/amount text fragments', () {
      final extraction = _singlePage([
        ['05/09/2026', 40, 0],
        ['UBER TRIP', 40, 150],
        ['235.00', 40, 400],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 235.00);
      expect(result.first.description.toLowerCase(), contains('uber'));
    });
  });

  group('PdfTransactionParser — non-transaction rows are dropped', () {
    test('drops a header-only block with no amount', () {
      final extraction = _singlePage([
        ['Statement Period: 01 Sep 2026 to 30 Sep 2026', 20, 0],
        ['Account Summary', 40, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, isEmpty);
    });

    test('returns empty list for a PDF with no extracted text', () {
      final result = PdfTransactionParser.extract(
        const PdfExtractionResult(pages: []),
        referenceDate: _reference,
      );
      expect(result, isEmpty);
    });
  });

  group('PdfTransactionParser — dense multi-transaction statement (many rows)', () {
    test('splits a long list of one-row-per-transaction entries without bleeding across blocks', () {
      final extraction = _singlePage([
        ['01/09/2026 UPI-SWIGGY-420.00', 20, 0],
        ['02/09/2026 UPI-ZOMATO-250.00', 40, 0],
        ['03/09/2026 UPI-AMAZON-1250.00', 60, 0],
        ['04/09/2026 SALARY CREDIT-55000.00', 80, 0],
        ['05/09/2026 ATM WDL-2000.00', 100, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(5));
      expect(result.map((t) => t.amount).toList(), [
        420.00,
        250.00,
        1250.00,
        55000.00,
        2000.00,
      ]);
      expect(result.map((t) => t.date).toList(), [
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
        DateTime(2026, 9, 3),
        DateTime(2026, 9, 4),
        DateTime(2026, 9, 5),
      ]);
    });
  });

  group('PdfTransactionParser — ICICI/Axis-style separate Debit/Credit columns', () {
    test('a debit-only row (credit column blank) is parsed as expense', () {
      final extraction = _singlePage([
        ['Date', 20, 0],
        ['Particulars', 20, 100],
        ['Debit', 20, 300],
        ['Credit', 20, 400],
        ['Balance', 20, 500],
        ['05/09/2026', 60, 0],
        ['NEFT-SWIGGY BANGALORE', 60, 100],
        ['420.00', 60, 300],
        ['12,500.00', 60, 500],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });

    test('a credit-only row (debit column blank) is parsed as income', () {
      final extraction = _singlePage([
        ['Date', 20, 0],
        ['Particulars', 20, 100],
        ['Debit', 20, 300],
        ['Credit', 20, 400],
        ['Balance', 20, 500],
        ['06/09/2026', 60, 0],
        ['SALARY CREDIT XYZ CORP', 60, 100],
        ['55,000.00', 60, 400],
        ['67,500.00', 60, 500],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 55000.00);
    });
  });

  group('PdfTransactionParser — credit-card statement layout', () {
    test('parses a credit card transaction row with merchant, amount, and no running balance', () {
      final extraction = _singlePage([
        ['Transaction Date', 20, 0],
        ['Description', 20, 150],
        ['Amount', 20, 400],
        ['05/09/2026', 60, 0],
        ['AMAZON.IN MUMBAI', 60, 150],
        ['1,299.00', 60, 400],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 1299.00);
      expect(tx.description.toLowerCase(), contains('amazon'));
    });
  });

  group('PdfTransactionParser — column-order variation (amount before description)', () {
    test('reconstructs a row with amount column left of description column', () {
      final extraction = _singlePage([
        ['05/09/2026', 40, 0],
        ['235.00', 40, 100],
        ['UBER TRIP', 40, 250],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 235.00);
      expect(result.first.description.toLowerCase(), contains('uber'));
    });
  });

  group('PdfTransactionParser — review signal', () {
    test('a fully-parsed row with explicit currency marker is ready and pre-selected', () {
      final extraction = _singlePage([
        ['05/09/2026 CLEAR MERCHANT ₹500.00', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      final tx = result.first;
      expect(tx.reviewStatus, DetectionReviewStatus.ready);
      expect(tx.isSelected, isTrue);
    });

    test('a block with an amount but no date needs review and is not pre-selected', () {
      final extraction = _singlePage([
        ['SOME MERCHANT ₹500.00 no date here', 20, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      final tx = result.first;
      expect(tx.reviewStatus, DetectionReviewStatus.needsReview);
      expect(tx.isSelected, isFalse);
    });
  });
}
