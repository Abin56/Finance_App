// Regression coverage for the block-boundary fix in `_groupIntoBlocks`
// (see `pdf_date_block_grouping_risk` in project memory): a date-shaped
// match must be anchored near the start of its row to force a new block,
// and a row carrying an amount while the current block is already
// date+amount-complete also forces a new block (covers date-last layouts).
//
// This file exercises several distinct synthetic bank-statement layouts
// against the new boundary logic specifically, on top of the existing
// layout coverage in pdf_transaction_parser_test.dart, per the requirement
// to check several different formats before trusting a foundational parser
// change.
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _reference = DateTime(2026, 9, 20);

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
  group('date-shaped noise inside narration must not fork a block', () {
    test('"valid thru" date-like substring does not split the block', () {
      final extraction = _singlePage([
        ['09/09/2026 UPI-BIGBASKET GROCERY', 20, 0],
        ['CARD VALID THRU 12 NOV OFFER APPLIED', 40, 0],
        ['890.00', 20, 300],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 890.00);
      expect(result.first.date, DateTime(2026, 9, 9));
    });

    test('a reference number containing a date-shaped digit run does not split', () {
      final extraction = _singlePage([
        ['06/09/2026 NEFT TXN REF 05SEP2412998', 20, 0],
        ['2200.00', 20, 300],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 2200.00);
      expect(result.first.date, DateTime(2026, 9, 6));
    });

    test('"expires 15 Dec" style trailer text on its own continuation line stays attached', () {
      final extraction = _singlePage([
        ['10/09/2026 SUBSCRIPTION RENEWAL', 20, 0],
        ['OFFER EXPIRES 15 DEC TERMS APPLY', 40, 0],
        ['499.00', 20, 300],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 499.00);
      expect(result.first.date, DateTime(2026, 9, 10));
    });

    test(
      'a buried date-shaped footnote must not be adopted as a dateless '
      'block\'s transaction date (Phase A: date-selection trust consistency)',
      () {
        // No row in this block has a date anchored at its own start — the
        // block-splitting guard already refuses to treat the footnote row
        // as a trusted date row (so it never forces a split), but before
        // Phase A, `_toDetectedTransaction`'s own date-search loop had no
        // such guard and would still pick up this buried date as "the"
        // block's date once the row ended up attached to it.
        final extraction = _singlePage([
          ['ACCOUNT SUMMARY HEADER TEXT', 20, 0],
          ['some plan effective from transactions dated 17-Nov-2011.', 40, 0],
          ['another unrelated summary line here', 60, 0],
        ]);
        final result = PdfTransactionParser.extract(
          extraction,
          referenceDate: _reference,
        );
        expect(
          result.where((t) => t.date == DateTime(2011, 11, 17)),
          isEmpty,
          reason: 'a date buried mid-sentence must never become a transaction date',
        );
      },
    );

    test(
      'a buried date in a continuation row does not leak into a real '
      'transaction\'s date when the block already has its own trusted date',
      () {
        final extraction = _singlePage([
          ['05/09/2026 SUBSCRIPTION RENEWAL', 20, 0],
          ['fine print: offer valid until dated 17-Nov-2011 terms apply', 40, 0],
          ['499.00', 20, 300],
        ]);
        final result = PdfTransactionParser.extract(
          extraction,
          referenceDate: _reference,
        );
        expect(result, hasLength(1));
        expect(result.first.amount, 499.00);
        expect(
          result.first.date,
          DateTime(2026, 9, 5),
          reason: 'the row\'s own trusted date must win over a buried date elsewhere in the block',
        );
      },
    );
  });

  group('legitimate date-first rows with no amount still surface for review', () {
    test('a standalone dated row with no amount forces its own block', () {
      final extraction = _singlePage([
        ['05/09/2026 SWIGGY 420.00', 20, 0],
        ['06/09/2026 UNKNOWN MERCHANT NO AMOUNT HERE', 40, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(2));
      final swiggy = result.firstWhere((t) => t.amount == 420.00);
      expect(swiggy.date, DateTime(2026, 9, 5));
      final unknown = result.firstWhere((t) => t.amount == null);
      expect(unknown.date, DateTime(2026, 9, 6));
      expect(unknown.isSelected, isFalse);
    });
  });

  group('date-last (receipt-style) layout — multiple transactions in sequence', () {
    test('two consecutive date-last transactions both keep their own date and amount', () {
      final extraction = _singlePage([
        ['AMAZON PAY - ONLINE PURCHASE', 20, 0],
        ['1,299.00', 40, 0],
        ['05 Sep 2026', 60, 0],
        ['UBER TRIP FARE', 80, 0],
        ['235.00', 100, 0],
        ['06 Sep 2026', 120, 0],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(2));
      expect(result[0].amount, 1299.00);
      expect(result[0].date, DateTime(2026, 9, 5));
      expect(result[1].amount, 235.00);
      expect(result[1].date, DateTime(2026, 9, 6));
    });
  });

  group('mixed layout — date-first transactions followed by a date-last one', () {
    test('a date-last transaction after a date-first block still gets its own amount/date', () {
      final extraction = _singlePage([
        ['15/09/2026 UPI-AMAZON PURCHASE', 20, 0],
        ['1499.00', 20, 300],
        ['ELECTRICITY BILL PAYMENT BESCOM', 40, 0],
        ['1150.00', 60, 0],
        ['16/09/2026', 80, 0],
        ['17/09/2026 UPI-DOMINOS PIZZA', 100, 0],
        ['560.00', 100, 300],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );

      final amazon = result.firstWhere((t) => t.amount == 1499.00);
      expect(amazon.date, DateTime(2026, 9, 15));

      final electricity = result.firstWhere((t) => t.amount == 1150.00);
      expect(
        electricity.date,
        DateTime(2026, 9, 16),
        reason: 'date-last row sandwiched between two date-first rows must keep its own date',
      );

      final dominos = result.firstWhere((t) => t.amount == 560.00);
      expect(dominos.date, DateTime(2026, 9, 17));
    });
  });

  group('three-column debit/credit/balance layout (ICICI/Axis/HDFC style)', () {
    test('a debit-only row across many transactions keeps correct per-row amounts', () {
      final extraction = _singlePage([
        ['Date', 10, 0],
        ['Narration', 10, 100],
        ['Withdrawal', 10, 300],
        ['Deposit', 10, 400],
        ['Balance', 10, 500],
        ['01/09/2026 UPI-SWIGGY', 30, 0],
        ['420.00', 30, 300],
        ['12500.00', 30, 500],
        ['02/09/2026 SALARY CREDIT', 50, 0],
        ['55000.00', 50, 400],
        ['67500.00', 50, 500],
        ['03/09/2026 ATM WDL', 70, 0],
        ['5000.00', 70, 300],
        ['62500.00', 70, 500],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(3));
      expect(result[0].amount, 420.00);
      expect(result[0].type, TransactionType.expense);
      expect(result[1].amount, 55000.00);
      expect(result[1].type, TransactionType.income);
      expect(result[2].amount, 5000.00);
      expect(result[2].type, TransactionType.expense);
    });
  });

  group('dense one-row-per-transaction statement — no boundary drift over many rows', () {
    test('20 sequential one-line transactions all detected with no bleed', () {
      final rows = List.generate(20, (i) {
        final day = (i + 1).toString().padLeft(2, '0');
        return [
          '$day/09/2026 MERCHANT $i',
          20.0 * (i + 1),
          0,
        ];
      });
      // Append distinct amounts as a second column per row.
      final withAmounts = <List<Object>>[];
      for (var i = 0; i < rows.length; i++) {
        withAmounts.add(rows[i]);
        withAmounts.add([
          '${(i + 1) * 10}.00',
          20.0 * (i + 1),
          300,
        ]);
      }
      final extraction = _singlePage(withAmounts);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(20));
      for (var i = 0; i < 20; i++) {
        expect(result[i].amount, (i + 1) * 10.0);
        expect(result[i].date, DateTime(2026, 9, i + 1));
      }
    });
  });

  group('multi-line description still merges correctly with the new boundary rules', () {
    test('a wrapped description line with no date/amount stays attached to its block', () {
      final extraction = _singlePage([
        ['05/09/2026', 20, 0],
        ['IMPS TRANSFER TO', 20, 100],
        ['420.00', 20, 450],
        ['JOHN DOE ACCOUNT SERVICES PRIVATE LIMITED', 60, 100],
        ['06/09/2026 NEXT TXN', 100, 0],
        ['100.00', 100, 300],
      ]);
      final result = PdfTransactionParser.extract(
        extraction,
        referenceDate: _reference,
      );
      expect(result, hasLength(2));
      expect(result[0].description, contains('IMPS'));
      expect(result[0].description, contains('JOHN DOE'));
      expect(result[0].amount, 420.00);
      expect(result[1].amount, 100.00);
    });
  });
}
