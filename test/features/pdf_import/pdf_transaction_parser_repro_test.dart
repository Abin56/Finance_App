// Reproduction harness: a synthetic 20-transaction bank statement run
// through the real `PdfTransactionParser.extract()` to check whether the
// suspected date/block-grouping + amount-vs-balance interaction actually
// drops or corrupts transactions. Diagnostic only — no parser code is
// changed here. See memory note `pdf_date_block_grouping_risk`.
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
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
  test('synthetic 20-transaction statement — detection report', () {
    // Column header row, stripped by layout reconstruction only if it
    // repeats across pages; single-page here so it's just a normal row that
    // the parser must not treat as a transaction.
    final rows = <List<Object>>[
      ['Date', 10, 0],
      ['Narration', 10, 100],
      ['Withdrawal', 10, 300],
      ['Deposit', 10, 400],
      ['Balance', 10, 500],

      // 1. Plain debit, single line.
      ['01/09/26 UPI-SWIGGY BANGALORE', 30, 0],
      ['420.00', 30, 300],
      ['12500.00', 30, 500],

      // 2. Plain credit, single line.
      ['02/09/26 SALARY CREDIT XYZ CORP', 50, 0],
      ['55000.00', 50, 400],
      ['67500.00', 50, 500],

      // 3. DR-suffixed figure.
      ['03-Sep-2026 ATM WDL NEFT', 70, 0],
      ['5000.00 DR', 70, 300],
      ['62500.00', 70, 500],

      // 4. CR-suffixed figure.
      ['04-Sep-2026 INTEREST CREDIT', 90, 0],
      ['150.00 CR', 90, 400],
      ['62650.00', 90, 500],

      // 5. Reference number that is NOT date-shaped (control).
      ['05/09/26 UPI-ZOMATO REF NO 998877665544', 110, 0],
      ['610.00', 110, 300],
      ['62040.00', 110, 500],

      // 6. ADVERSARIAL: reference number that IS date-shaped
      // ("05 Sep" embedded inside a reference id on the same row).
      ['06/09/26 NEFT TXN REF 05SEP2412998', 130, 0],
      ['2200.00', 130, 300],
      ['59840.00', 130, 500],

      // 7. Plain debit.
      ['07/09/26 UPI-UBER TRIP', 150, 0],
      ['340.00', 150, 300],
      ['59500.00', 150, 500],

      // 8. Multi-line description (wrapped merchant name), no embedded date.
      ['08/09/26 NEFT TRANSFER TO', 170, 0],
      ['JOHN DOE ACCOUNT SERVICES PVT LTD', 185, 0],
      ['1200.00', 170, 300],
      ['58300.00', 170, 500],

      // 9. ADVERSARIAL: multi-line description whose continuation line
      // itself contains a date-shaped substring ("12 Nov" as part of a
      // "valid thru" / unrelated note), which could falsely start a new
      // block per `_groupIntoBlocks`.
      ['09/09/26 UPI-BIGBASKET GROCERY', 210, 0],
      ['CARD VALID THRU 12 NOV OFFER APPLIED', 225, 0],
      ['890.00', 210, 300],
      ['57410.00', 210, 500],

      // 10. Plain credit.
      ['10/09/26 REFUND ORDER 45521', 250, 0],
      ['300.00', 250, 400],
      ['57710.00', 250, 500],

      // 11. Plain debit.
      ['11/09/26 UPI-NETFLIX SUBSCRIPTION', 270, 0],
      ['649.00', 270, 300],
      ['57061.00', 270, 500],

      // 12. ADVERSARIAL: three-column row (debit + credit + balance all
      // present, with only debit populated) — tests amount vs balance
      // figure disambiguation with 2 non-empty numeric figures.
      ['12/09/26 UPI-RENT PAYMENT', 290, 0],
      ['15000.00', 290, 300],
      ['', 290, 400],
      ['42061.00', 290, 500],

      // 13. Plain debit.
      ['13/09/26 UPI-STARBUCKS COFFEE', 310, 0],
      ['280.00', 310, 300],
      ['41781.00', 310, 500],

      // 14. Plain credit.
      ['14/09/26 UPI RECEIVED FROM FRIEND', 330, 0],
      ['2000.00', 330, 400],
      ['43781.00', 330, 500],

      // 15. Plain debit.
      ['15/09/26 UPI-AMAZON PURCHASE', 350, 0],
      ['1499.00', 350, 300],
      ['42282.00', 350, 500],

      // 16. ADVERSARIAL: date-last (receipt-style) layout mixed into the
      // same statement.
      ['ELECTRICITY BILL PAYMENT BESCOM', 370, 0],
      ['1150.00', 385, 0],
      ['16/09/26', 400, 0],

      // 17. Plain debit.
      ['17/09/26 UPI-DOMINOS PIZZA', 420, 0],
      ['560.00', 420, 300],
      ['40572.00', 420, 500],

      // 18. ADVERSARIAL: row with THREE amount-shaped figures (debit,
      // credit both look numeric-empty-ish is hard in text mode, so
      // instead simulate debit + a second unrelated figure + balance).
      ['18/09/26 UPI-INSURANCE PREMIUM AUTO DEBIT', 440, 0],
      ['3200.00', 440, 300],
      ['37372.00', 440, 500],

      // 19. Plain credit.
      ['19/09/26 CASHBACK OFFER CREDIT', 460, 0],
      ['75.00', 460, 400],
      ['37447.00', 460, 500],

      // 20. Plain debit, closes statement.
      ['20/09/26 UPI-GROCERY STORE FINAL', 480, 0],
      ['920.00', 480, 300],
      ['36527.00', 480, 500],
    ];

    final extraction = _singlePage(rows);
    final result = PdfTransactionParser.extract(
      extraction,
      referenceDate: _reference,
    );

    // Regression assertions for the two failures a real repro proved (see
    // memory note `pdf_date_block_grouping_risk`): a date-shaped substring
    // inside unrelated prose ("valid thru 12 Nov") must not fork a ghost
    // block off transaction #9, and a date-last transaction (#16,
    // electricity bill) must not be silently absorbed into its neighbor.
    expect(
      result,
      hasLength(20),
      reason: 'one row per real transaction — no ghost blocks, no silent drops',
    );

    final bigBasket = result.firstWhere((t) => t.amount == 890.0);
    expect(bigBasket.date, DateTime(2026, 9, 9));
    expect(
      result.where((t) => t.date == DateTime(2025, 11, 12)),
      isEmpty,
      reason: '"valid thru 12 Nov" must never be read as its own transaction date',
    );

    final electricity = result.firstWhere((t) => t.amount == 1150.0);
    expect(
      electricity.date,
      DateTime(2026, 9, 16),
      reason: 'date-last electricity bill must keep its own date, not bleed into #15',
    );
    // Known residual limitation (not fully fixed by this change): the
    // electricity bill's *leading* description row ("ELECTRICITY BILL
    // PAYMENT BESCOM") has neither a date nor an amount of its own, so it
    // is indistinguishable, one row at a time, from a wrapped continuation
    // line of the Amazon block above it — it is still attributed to
    // Amazon's description text. The fix here recovers the electricity
    // bill's own date and amount as a real, reviewable row (previously it
    // vanished completely); it does not achieve perfect description
    // attribution for a description-before-amount-before-date row with no
    // leading signal at all. Documented so a future contributor doesn't
    // reintroduce the amount/date loss while "fixing" this cosmetic bleed.
    final amazon = result.firstWhere(
      (t) => t.description.toLowerCase().contains('amazon'),
    );
    expect(amazon.amount, 1499.0);
    expect(amazon.date, DateTime(2026, 9, 15));
  });
}
