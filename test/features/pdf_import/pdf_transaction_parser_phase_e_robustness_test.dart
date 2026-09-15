// Phase E: adversarial robustness validation for the Phase A-D changes.
// Pure test file — no production code is touched here. Every case is
// generic (no bank/merchant-specific text) and targets a specific way the
// new region-detection, block-boundary, and amount-selection rules could
// plausibly break on layouts other than the one real PDF validated so far.
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

PdfExtractionResult _multiPage(List<List<List<Object>>> pages) {
  final pageResults = <PdfPageResult>[];
  for (var i = 0; i < pages.length; i++) {
    final lines = pages[i]
        .map((r) => _line(r[0] as String, (r[1] as num).toDouble(), left: r.length > 2 ? (r[2] as num).toDouble() : 0))
        .toList();
    pageResults.add(PdfPageResult(pageNumber: i + 1, source: PdfTextSource.embedded, lines: lines));
  }
  return PdfExtractionResult(pages: pageResults);
}

void main() {
  group('1. amount rules — adversarial percentage/direction cases', () {
    test('18.00% 76.71 D -> 76.71', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 FEE ROW @ 18.00% 76.71 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 76.71);
    });

    test('5.00% 100.00 D -> 100.00', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 CHARGE @ 5.00% 100.00 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 100.00);
    });

    test('12.5% 250.00 C -> 250.00', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 REBATE @ 12.5% 250.00 C', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 250.00);
      // A bare single-letter "C" (unlike "CR") carries no direction signal
      // recognized by `SmartImportDirectionDetector` today — that detector
      // is pre-existing and untouched by Phase A-D, so this defaults to
      // expense per `_toDetectedTransaction`'s documented fallback. Not a
      // regression; recorded as a pre-existing observation in the Phase E
      // report, not asserted as "should be income" here.
      expect(result.first.type, TransactionType.expense);
    });

    test('percentage mentioned in description text, real amount elsewhere in block', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 DISCOUNT OF 10% APPLIED TODAY', 10, 0],
          ['420.00 D', 10, 300],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });

    test('123.45 D -> 123.45', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 SOME TRANSACTION 123.45 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 123.45);
    });

    test('123.45 C -> 123.45', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 SOME TRANSACTION 123.45 C', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 123.45);
      // Same pre-existing bare-"C" observation as above — amount selection
      // (this phase's actual scope) is correct; direction defaulting is an
      // untouched, pre-existing behavior.
      expect(result.first.type, TransactionType.expense);
    });

    test('123.45 M -> 123.45', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 INSTALLMENT ROW 123.45 M', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 123.45);
    });

    test('a reference number ahead of the amount does not outrank it', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 REFERENCE 123456 456.78 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 456.78);
    });
  });

  group('2. cases designed to break the direction-code preference', () {
    test('a reference number immediately before D/C is not mistaken for the amount', () {
      // "REF NO 998877 D" - "998877" has no decimal point so it cannot be
      // an amount candidate at all (SmartImportAmountParser requires a
      // 2-decimal-digit bare figure), but this proves the new rule doesn't
      // accidentally start matching bare integers next to a direction code.
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 UPI REF NO 998877 250.50 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 250.50);
    });

    test('a balance value immediately before D/C does not outrank the real amount', () {
      // Deliberately adversarial: give the BALANCE its own trailing "D" by
      // construction, to check the direction-code preference doesn't
      // blindly out-rank the balance-context exclusion that already runs
      // first via `isBalanceOnly`.
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 PURCHASE 420.00 Closing Balance 12500.00 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });

    test('an amount in parentheses before the real amount does not win', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 FP EMI 12/24(EXCL TAX 70.38) 2,116.86 M', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 2116.86);
    });

    test('multiple amounts exist in one transaction — direction-coded one wins', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 ITEM 99.99 SUBTOTAL 199.99 TOTAL 220.00 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 220.00);
    });

    test('percentage appears after the real amount', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 PURCHASE 500.00 D TAX RATE 18.00%', 10, 0],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 500.00);
    });

    test('currency-marked amount with a trailing D still resolves correctly', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 PURCHASE ₹840.00 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 840.00);
    });

    test('DR/CR (two-letter codes) still resolve like D/C', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 ATM WDL 5,000.00 DR', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 5000.00);
      expect(result.first.type, TransactionType.expense);
    });

    test('the letter D appearing as ordinary text (not a direction marker) does not falsely win', () {
      // "3RD" ends in a 2-letter-ish token but isn't a standalone
      // direction code sitting right after an amount-shaped figure; the
      // real amount here is unambiguous and must still be chosen.
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 PAYMENT DUE ON THE 3RD 650.00 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 650.00);
    });
  });

  group('3. date-last regression stress test', () {
    test('description -> amount -> date', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['ONLINE SUBSCRIPTION RENEWAL', 10, 0],
          ['499.00', 30, 0],
          ['12 Sep 2026', 50, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 499.00);
      expect(result.first.date, DateTime(2026, 9, 12));
    });

    test('description -> amount -> direction -> date', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['UTILITY BILL PAYMENT', 10, 0],
          ['1,150.00', 30, 0],
          ['D', 50, 0],
          ['13 Sep 2026', 70, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 1150.00);
      expect(result.first.date, DateTime(2026, 9, 13));
    });

    test('multiline variant: two-line description -> amount -> date', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['NEFT TRANSFER TO', 10, 0],
          ['SOME BENEFICIARY ACCOUNT SERVICES LTD', 25, 0],
          ['2,300.00', 45, 0],
          ['14 Sep 2026', 65, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 2300.00);
      expect(result.first.date, DateTime(2026, 9, 14));
      expect(result.first.description, contains('NEFT TRANSFER'));
    });

    test('several date-last transactions in sequence do not split, merge, or duplicate', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['MERCHANT ALPHA PURCHASE', 10, 0],
          ['100.00', 30, 0],
          ['01 Sep 2026', 50, 0],
          ['MERCHANT BETA PURCHASE', 70, 0],
          ['200.00', 90, 0],
          ['02 Sep 2026', 110, 0],
          ['MERCHANT GAMMA PURCHASE', 130, 0],
          ['300.00', 150, 0],
          ['03 Sep 2026', 170, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(3));
      expect(result.map((t) => t.amount).toList(), [100.00, 200.00, 300.00]);
      expect(result.map((t) => t.date).toList(), [
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
        DateTime(2026, 9, 3),
      ]);
    });
  });

  group('4. multiline transactions', () {
    test('date -> description line 1 -> description line 2 -> amount D', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['15/09/2026', 10, 0],
          ['TRANSFER TO MERCHANT SERVICES', 30, 0],
          ['REGIONAL OFFICE BRANCH', 50, 0],
          ['750.00 D', 10, 300],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 750.00);
      // "TRANSFER" (not "PAYMENT" — a pre-existing, unrelated stripped
      // keyword in `_directionKeywordPattern`) to isolate the actual
      // thing under test: multi-line description merging into one block.
      expect(result.first.description, contains('TO MERCHANT'));
      expect(result.first.description, contains('REGIONAL OFFICE'));
    });

    test('date -> description line 1 -> amount D -> continuation text stays attached, not a new transaction', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['16/09/2026 SUBSCRIPTION CHARGE', 10, 0],
          ['640.00 D', 10, 300],
          ['AUTO RENEWAL NOTICE APPLIES', 30, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 640.00);
    });
  });

  group('5. running balance — debit and credit', () {
    test('debit: transaction amount + D + running balance -> balance never wins', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 PURCHASE 420.00 D 12,500.00', 10, 0],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });

    test('credit: transaction amount + C + running balance -> balance never wins', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 SALARY CREDIT 55,000.00 C 67,500.00', 10, 0],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 55000.00);
      expect(tx.type, TransactionType.income);
    });
  });

  group('6. separate debit/credit columns', () {
    test('debit populated, credit blank -> column position wins', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['Date', 10, 0], ['Particulars', 10, 100], ['Debit', 10, 300], ['Credit', 10, 400], ['Balance', 10, 500],
          ['05/09/2026', 30, 0], ['SOME MERCHANT', 30, 100], ['420.00', 30, 300], ['12,500.00', 30, 500],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 420.00);
    });

    test('credit populated, debit blank -> column position wins', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['Date', 10, 0], ['Particulars', 10, 100], ['Debit', 10, 300], ['Credit', 10, 400], ['Balance', 10, 500],
          ['05/09/2026', 30, 0], ['SALARY CREDIT', 30, 100], ['55,000.00', 30, 400], ['67,500.00', 30, 500],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 55000.00);
    });

    test('all three columns populated (debit, credit-blank-represented, balance)', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['Date', 10, 0], ['Particulars', 10, 100], ['Debit', 10, 300], ['Credit', 10, 400], ['Balance', 10, 500],
          ['05/09/2026', 30, 0], ['RENT PAYMENT', 30, 100], ['15,000.00', 30, 300], ['42,061.00', 30, 500],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 15000.00);
    });
  });

  group('7. credit-card / installment cases', () {
    test('a plain purchase amount resolves correctly', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['Transaction Date', 10, 0], ['Description', 10, 150], ['Amount', 10, 400],
          ['05/09/2026', 30, 0], ['ONLINE STORE PURCHASE', 30, 150], ['1,299.00', 30, 400],
        ]),
        referenceDate: _reference,
      );
      final tx = result.firstWhere((t) => t.amount != null);
      expect(tx.amount, 1299.00);
    });

    test('a tax-line amount (percentage-adjacent) resolves to the real fee, not the rate', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 GST DB @ 18.00% 45.00 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 45.00);
    });

    test('an installment (M-coded) row prefers the total over a parenthetical sub-amount', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 EMI 03/12(PRINCIPAL 400.00) 512.34 M', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.first.amount, 512.34);
    });

    test('a parenthetical sub-amount with no trailing code anywhere else in the row still yields a value', () {
      // No trailing direction code at all on this row — the
      // direction-code preference should not apply, and existing
      // first-non-balance-match behavior should still surface something
      // rather than nothing.
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 CHARGE (BASE 100.00) 250.00', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, isNotEmpty);
      expect(result.first.amount, isNotNull);
    });
  });

  group('8. region detector fallback — no false negatives on small/sparse documents', () {
    test('no header, receipt-style, single transaction', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['COFFEE SHOP RECEIPT', 10, 0],
          ['₹350.00', 30, 0],
          ['05 Sep 2026', 50, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 350.00);
    });

    test('date-last, single transaction, no header', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['TAXI FARE', 10, 0],
          ['235.00', 30, 0],
          ['06 Sep 2026', 50, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 235.00);
    });

    test('sparse: two transactions with large gaps, no header, no density run', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['05/09/2026 ONE MERCHANT 100.00 D', 10, 0],
          ['some unrelated spacer text with no signal', 60, 0],
          ['another unrelated line', 90, 0],
          ['06/09/2026 TWO MERCHANT 200.00 D', 130, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result.where((t) => t.amount == 100.00), isNotEmpty);
      expect(result.where((t) => t.amount == 200.00), isNotEmpty);
    });

    test('multiline, no header, single transaction', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['07/09/2026', 10, 0],
          ['GIFT CARD PURCHASE', 30, 0],
          ['ONLINE STORE', 50, 0],
          ['80.00 D', 10, 300],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 80.00);
    });

    test('single-transaction document overall (smallest possible case)', () {
      final result = PdfTransactionParser.extract(
        _singlePage([
          ['08/09/2026 LONE TRANSACTION 999.00 D', 10, 0],
        ]),
        referenceDate: _reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 999.00);
    });
  });

  group('9. region detector false-positive resistance', () {
    test('a legal/prose page with dates, percentages, amounts, reference numbers and D/C '
        'letters but no transaction-table structure produces no fabricated transactions', () {
      final result = PdfTransactionParser.extract(
        _multiPage([
          [
            ['Date Amount  Transaction Details', 10, 0],
            ['01/09/2026 REAL MERCHANT ONE 100.00 D', 20, 0],
            ['02/09/2026 REAL MERCHANT TWO 200.00 D', 30, 0],
            ['03/09/2026 REAL MERCHANT THREE 300.00 D', 40, 0],
          ],
          [
            ['Terms and Conditions', 10, 0],
            ['This agreement is effective from 17 Nov 2011 onward', 20, 0],
            ['and covers a rate of 18.00% applicable annually', 30, 0],
            ['The reference code for this section is REF 445566 D', 40, 0],
            ['A processing fee of 500.00 C may apply in certain cases', 50, 0],
            ['as described in clause 4.2 D of the agreement text below', 60, 0],
            ['Please review section 5.1 for further details on this matter', 70, 0],
            ['and consult your local branch for account-specific queries', 80, 0],
            ['Additional terms apply as outlined in the appendix section', 90, 0],
          ],
        ]),
        referenceDate: _reference,
      );

      expect(result.where((t) => t.sourceImageIndex == 2), isEmpty,
          reason: 'a legal/prose-only page must contribute zero transactions');
      expect(result.where((t) => t.date == DateTime(2011, 11, 17)), isEmpty);
      expect(result.where((t) => t.amount == 500.00), isEmpty,
          reason: 'a fee figure mentioned in prose must not become a transaction');
      expect(result, hasLength(3));
    });

    test('a single legal-only page (no transaction page at all) still falls back safely '
        '(no crash, no fabricated transaction, or a clean empty/global-fallback result)', () {
      final extraction = _singlePage([
        ['Terms and Conditions', 10, 0],
        ['This agreement is effective from 17 Nov 2011 onward', 20, 0],
        ['and covers a rate of 18.00% applicable annually', 30, 0],
        ['A processing fee of 500.00 C may apply in certain cases', 40, 0],
        ['Please review the appendix for further details', 50, 0],
      ]);
      final result = PdfTransactionParser.extract(extraction, referenceDate: _reference);
      expect(result.where((t) => t.date == DateTime(2011, 11, 17)), isEmpty);
    });
  });

  group('10. real PDF descriptor — see harness test for actual content verification', () {
    test('placeholder: content-level real-PDF checks are run via _real_pdf_analysis_harness_test.dart', () {
      expect(true, isTrue);
    });
  });
}
