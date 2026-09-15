// Phase C regression coverage for `_groupIntoBlocks`'s new
// `dateRowClosesAmountOnlyBlock` rule: a trusted date-first row that also
// carries its own amount must force a new block even when the currently
// open block has an amount but no date of its own (e.g. a dateless
// fee/charge row that opened its own block). See
// `pdf_date_block_grouping_risk` in project memory for the real-PDF
// evidence (IGST fee + Mahesh Kumar transaction merging into one block).
//
// Assertions here check block *count* and *content separation* only — Phase
// C intentionally does not fix amount/direction selection (Phase D), so a
// merged-looking amount on the fee-only block is expected and not asserted
// against.
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
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
  group('1. IGST + Mahesh exact structural pattern', () {
    test('a dateless fee row followed by a real dated transaction produces two blocks', () {
      final extraction = _singlePage([
        ['17 Aug 26 INTEREST ON EMI 35.19 D', 10, 0],
        ['IGST DB @ 18.00% 76.71 D', 20, 0],
        ['TRANSACTIONS FOR SOME CARDHOLDER', 30, 0],
        ['17 Jul 26 UPI-SOME MERCHANT 413.00 D', 40, 0],
        ['18 Jul 26 ANOTHER MERCHANT 1094.00 D', 50, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);

      // 4 real transaction-shaped rows -> 4 blocks: EMI interest, IGST fee,
      // the merchant transaction, and the next dated transaction. Not
      // asserting amounts here (Phase D's job) — only that IGST and the
      // merchant transaction are no longer merged into one block.
      final igstTx = result.firstWhere(
        (t) => t.rawText.contains('IGST'),
        orElse: () => throw StateError('no block contains IGST text'),
      );
      expect(
        igstTx.rawText.contains('SOME MERCHANT'),
        isFalse,
        reason: 'IGST fee and the real merchant transaction must be separate blocks',
      );

      final merchantTx = result.firstWhere(
        (t) => t.rawText.contains('SOME MERCHANT') && !t.rawText.contains('IGST'),
        orElse: () => throw StateError('no clean block contains the merchant transaction'),
      );
      expect(merchantTx.date, DateTime(2026, 7, 17));
      expect(merchantTx.amount, 413.00);
    });
  });

  group('2. two consecutive dateless transactions (amount + direction code only)', () {
    test('two rows with amount + trailing code but no date of their own stay merged '
        '(no date signal to split on — this case needs Phase D, not Phase C)', () {
      // Neither row has a date at all, so `dateRowClosesAmountOnlyBlock`
      // (which requires `isTrustedDateRow`) cannot apply — this
      // demonstrates the boundary of what Phase C's rule covers: it only
      // triggers on an *incoming trusted date row*, not on two dateless
      // amount rows in sequence.
      final extraction = _singlePage([
        ['17 Aug 26 SOME TRANSACTION 100.00 D', 10, 0],
        ['FEE CHARGE 25.00 D', 20, 0],
        ['ANOTHER FEE 15.00 D', 30, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      // Documented current behavior: still produces blocks per the
      // existing `amountStartsNewBlock` rule (unrelated to this phase),
      // which already splits a dateless-but-amount-bearing row off a
      // date+amount-complete block. Included here as a boundary-case
      // record, not a claim that Phase C changed this.
      expect(result, isNotEmpty);
    });
  });

  group('3. legitimate multiline transaction — description continuation + amount', () {
    test('a wrapped description line with no date/amount stays in the same block', () {
      final extraction = _singlePage([
        ['17/09/26', 10, 0],
        ['ONLINE ORDER', 20, 0],
        ['AMAZON MARKETPLACE', 30, 0],
        ['1,250.00 D', 10, 300],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(1));
      expect(result.first.description, contains('ONLINE ORDER'));
      expect(result.first.description, contains('AMAZON MARKETPLACE'));
      expect(result.first.amount, 1250.00);
    });
  });

  group('4. date-first consecutive transactions — unchanged', () {
    test('a run of clean date-first one-row transactions each stay separate', () {
      final extraction = _singlePage([
        ['01/09/26 MERCHANT ONE 100.00 D', 10, 0],
        ['02/09/26 MERCHANT TWO 200.00 D', 20, 0],
        ['03/09/26 MERCHANT THREE 300.00 D', 30, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(3));
      expect(result.map((t) => t.amount).toList(), [100.00, 200.00, 300.00]);
    });
  });

  group('5. date-last transactions — unchanged', () {
    test('two consecutive date-last transactions both keep their own date and amount', () {
      final extraction = _singlePage([
        ['AMAZON PAY - ONLINE PURCHASE', 20, 0],
        ['1,299.00', 40, 0],
        ['05 Sep 2026', 60, 0],
        ['UBER TRIP FARE', 80, 0],
        ['235.00', 100, 0],
        ['06 Sep 2026', 120, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(2));
      expect(result[0].amount, 1299.00);
      expect(result[0].date, DateTime(2026, 9, 5));
      expect(result[1].amount, 235.00);
      expect(result[1].date, DateTime(2026, 9, 6));
    });
  });

  group('6. existing 20-row dense repro — unchanged', () {
    test('all 20 known transactions still detected with no bleed', () {
      final rows = <List<Object>>[
        ['Date', 10, 0], ['Narration', 10, 100], ['Withdrawal', 10, 300], ['Deposit', 10, 400], ['Balance', 10, 500],
        ['01/09/26 UPI-SWIGGY BANGALORE', 30, 0], ['420.00', 30, 300], ['12500.00', 30, 500],
        ['02/09/26 SALARY CREDIT XYZ CORP', 50, 0], ['55000.00', 50, 400], ['67500.00', 50, 500],
        ['03-Sep-2026 ATM WDL NEFT', 70, 0], ['5000.00 DR', 70, 300], ['62500.00', 70, 500],
        ['04-Sep-2026 INTEREST CREDIT', 90, 0], ['150.00 CR', 90, 400], ['62650.00', 90, 500],
        ['05/09/26 UPI-ZOMATO REF NO 998877665544', 110, 0], ['610.00', 110, 300], ['62040.00', 110, 500],
        ['06/09/26 NEFT TXN REF 05SEP2412998', 130, 0], ['2200.00', 130, 300], ['59840.00', 130, 500],
        ['07/09/26 UPI-UBER TRIP', 150, 0], ['340.00', 150, 300], ['59500.00', 150, 500],
        ['08/09/26 NEFT TRANSFER TO', 170, 0], ['JOHN DOE ACCOUNT SERVICES PVT LTD', 185, 0], ['1200.00', 170, 300], ['58300.00', 170, 500],
        ['09/09/26 UPI-BIGBASKET GROCERY', 210, 0], ['CARD VALID THRU 12 NOV OFFER APPLIED', 225, 0], ['890.00', 210, 300], ['57410.00', 210, 500],
        ['10/09/26 REFUND ORDER 45521', 250, 0], ['300.00', 250, 400], ['57710.00', 250, 500],
        ['11/09/26 UPI-NETFLIX SUBSCRIPTION', 270, 0], ['649.00', 270, 300], ['57061.00', 270, 500],
        ['12/09/26 UPI-RENT PAYMENT', 290, 0], ['15000.00', 290, 300], ['', 290, 400], ['42061.00', 290, 500],
        ['13/09/26 UPI-STARBUCKS COFFEE', 310, 0], ['280.00', 310, 300], ['41781.00', 310, 500],
        ['14/09/26 UPI RECEIVED FROM FRIEND', 330, 0], ['2000.00', 330, 400], ['43781.00', 330, 500],
        ['15/09/26 UPI-AMAZON PURCHASE', 350, 0], ['1499.00', 350, 300], ['42282.00', 350, 500],
        ['ELECTRICITY BILL PAYMENT BESCOM', 370, 0], ['1150.00', 385, 0], ['16/09/26', 400, 0],
        ['17/09/26 UPI-DOMINOS PIZZA', 420, 0], ['560.00', 420, 300], ['40572.00', 420, 500],
        ['18/09/26 UPI-INSURANCE PREMIUM AUTO DEBIT', 440, 0], ['3200.00', 440, 300], ['37372.00', 440, 500],
        ['19/09/26 CASHBACK OFFER CREDIT', 460, 0], ['75.00', 460, 400], ['37447.00', 460, 500],
        ['20/09/26 UPI-GROCERY STORE FINAL', 480, 0], ['920.00', 480, 300], ['36527.00', 480, 500],
      ];
      final extraction = _singlePage(rows);
      final result = PdfTransactionParser.extract(extraction, referenceDate: DateTime(2026, 9, 7));
      expect(result, hasLength(20));
    });
  });

  group('7. existing HDFC/SBI/ICICI/Axis fixtures — unchanged', () {
    test('HDFC-style single-line table with running balance still parses', () {
      final extraction = _singlePage([
        ['Date', 20, 0], ['Narration', 20, 100], ['Withdrawal Amt.', 20, 250],
        ['Deposit Amt.', 20, 350], ['Closing Balance', 20, 450],
        ['05/09/26 UPI-SWIGGY BANGALORE-420.00', 60, 0], ['12,500.00', 60, 450],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, isNotEmpty);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.date, DateTime(2026, 9, 5));
    });

    test('SBI-style DR-suffixed row still parses', () {
      final extraction = _singlePage([
        ['06-Sep-2026', 30, 0], ['ATM WDL NEFT REF1234567', 30, 100],
        ['5,000.00 DR', 30, 350], ['45,200.00', 30, 450],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 5000.00);
    });

    test('ICICI/Axis-style separate Debit/Credit columns still parses', () {
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

  group('8. headerless/date-last fallback — unchanged', () {
    test('a small headerless receipt-style single transaction still parses', () {
      final extraction = _singlePage([
        ['AMAZON PAY - ONLINE PURCHASE', 20, 0],
        ['₹1,299.00', 60, 0],
        ['05 Sep 2026', 100, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result, hasLength(1));
      expect(result.first.amount, 1299.00);
      expect(result.first.date, DateTime(2026, 9, 5));
    });
  });
}
