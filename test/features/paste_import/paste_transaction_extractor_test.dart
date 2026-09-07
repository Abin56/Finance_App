import 'package:finance_app/features/paste_import/domain/paste_transaction_extractor.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reference = DateTime(2026, 9, 7);

  group('PasteTransactionExtractor — format 1 (date merchant amount DR/CR per line)', () {
    test('parses a single transaction line', () {
      final result = PasteTransactionExtractor.extract(
        '05 Sep SWIGGY 420 DR',
        referenceDate: reference,
      );
      expect(result, hasLength(1));
      expect(result.first.date, DateTime(2026, 9, 5));
      expect(result.first.amount, 420.0);
      expect(result.first.type, TransactionType.expense);
      expect(result.first.rawDescription, contains('Swiggy'));
    });

    test('parses multiple transaction lines', () {
      final result = PasteTransactionExtractor.extract(
        '05 Sep SWIGGY 420 DR\n05 Sep AMAZON 1299 DR\n06 Sep UBER 185.50 DR',
        referenceDate: reference,
      );
      expect(result, hasLength(3));
      expect(result[0].amount, 420.0);
      expect(result[1].amount, 1299.0);
      expect(result[2].amount, 185.50);
      expect(result.every((t) => t.type == TransactionType.expense), isTrue);
    });
  });

  group('PasteTransactionExtractor — format 2 (blank-line separated, date/merchant/amount)', () {
    test('parses multi-line blocks separated by blank lines', () {
      final text = '05/09/2026\nSWIGGY\n₹420.00\n\n05/09/2026\nAMAZON\n₹1,299.00';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result, hasLength(2));
      expect(result[0].date, DateTime(2026, 9, 5));
      expect(result[0].amount, 420.0);
      expect(result[0].rawDescription, contains('Swiggy'));
      expect(result[1].amount, 1299.0);
      expect(result[1].rawDescription, contains('Amazon'));
    });
  });

  group('PasteTransactionExtractor — format 3 (UPI dash-dated, Debit wording)', () {
    test('parses dash-separated dates with Debit wording', () {
      final text = '05-09-26 UPI-SWIGGY 420.00 Debit\n06-09-26 UBER INDIA 185.50 Debit';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result, hasLength(2));
      expect(result[0].date, DateTime(2026, 9, 5));
      expect(result[0].amount, 420.0);
      expect(result[0].type, TransactionType.expense);
      expect(result[1].date, DateTime(2026, 9, 6));
    });
  });

  group('PasteTransactionExtractor — format 4 (Mon dd merchant amount, columns)', () {
    test('parses month-first dates with currency-marked amounts', () {
      final text = 'Sep 05    Swiggy    ₹420\nSep 05    Amazon    ₹1,299\nSep 06    Uber      ₹185.50';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result, hasLength(3));
      expect(result[0].amount, 420.0);
      expect(result[1].amount, 1299.0);
      expect(result[2].amount, 185.50);
    });
  });

  group('PasteTransactionExtractor — format 5 (blank-line separated, merchant/date/amount)', () {
    test('parses multi-line blocks regardless of field order', () {
      final text = 'SWIGGY\n05 Sep\n₹420.00\n\nAMAZON\n05 Sep\n₹1,299.00';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result, hasLength(2));
      expect(result[0].date, DateTime(2026, 9, 5));
      expect(result[0].amount, 420.0);
      expect(result[0].rawDescription, contains('Swiggy'));
      expect(result[1].amount, 1299.0);
      expect(result[1].rawDescription, contains('Amazon'));
    });
  });

  group('PasteTransactionExtractor — amount formats', () {
    test('handles currency symbol, commas and INR marker without misreading them', () {
      expect(
        PasteTransactionExtractor.extract('05 Sep TEST ₹1,299.00 DR', referenceDate: reference)
            .first
            .amount,
        1299.0,
      );
      expect(
        PasteTransactionExtractor.extract('05 Sep TEST INR 1,299.00 DR', referenceDate: reference)
            .first
            .amount,
        1299.0,
      );
    });

    test('does not misread a comma-grouped amount as a decimal (1,299 -> 1299.00, not 1.299)', () {
      final result = PasteTransactionExtractor.extract(
        '05 Sep TEST 1,299 DR',
        referenceDate: reference,
      );
      expect(result.first.amount, 1299.0);
    });
  });

  group('PasteTransactionExtractor — debit/credit detection', () {
    test('DR maps to expense and CR maps to income', () {
      final debit = PasteTransactionExtractor.extract('05 Sep TEST 420 DR', referenceDate: reference);
      final credit = PasteTransactionExtractor.extract('05 Sep TEST 500 CR', referenceDate: reference);
      expect(debit.first.type, TransactionType.expense);
      expect(credit.first.type, TransactionType.income);
    });

    test('recognizes wordy debit/credit indicators', () {
      expect(
        PasteTransactionExtractor.extract('05 Sep TEST 420 Received', referenceDate: reference)
            .first
            .type,
        TransactionType.income,
      );
      expect(
        PasteTransactionExtractor.extract('05 Sep TEST 420 Spent', referenceDate: reference)
            .first
            .type,
        TransactionType.expense,
      );
    });
  });

  group('PasteTransactionExtractor — date formats', () {
    test('parses slash, dash and ISO dates', () {
      expect(
        PasteTransactionExtractor.extract('05/09/2026 TEST 420 DR', referenceDate: reference)
            .first
            .date,
        DateTime(2026, 9, 5),
      );
      expect(
        PasteTransactionExtractor.extract('05-09-2026 TEST 420 DR', referenceDate: reference)
            .first
            .date,
        DateTime(2026, 9, 5),
      );
      expect(
        PasteTransactionExtractor.extract('2026-09-05 TEST 420 DR', referenceDate: reference)
            .first
            .date,
        DateTime(2026, 9, 5),
      );
      expect(
        PasteTransactionExtractor.extract('Sep 05 TEST 420 DR', referenceDate: reference)
            .first
            .date,
        DateTime(2026, 9, 5),
      );
    });
  });

  group('PasteTransactionExtractor — merchant/description', () {
    test('preserves multi-word merchant names without truncating', () {
      final result = PasteTransactionExtractor.extract(
        '05 Sep UBER INDIA SYSTEMS 420 DR',
        referenceDate: reference,
      );
      expect(result.first.rawDescription, contains('Uber India Systems'));
    });
  });

  group('PasteTransactionExtractor — invalid/ambiguous input', () {
    test('ignores lines with neither a date nor an amount', () {
      final result = PasteTransactionExtractor.extract(
        'Statement for account ending 1234\n05 Sep SWIGGY 420 DR',
        referenceDate: reference,
      );
      expect(result, hasLength(1));
      expect(result.first.amount, 420.0);
    });

    test('returns an empty list for text with no recognizable transactions', () {
      final result = PasteTransactionExtractor.extract(
        'Thank you for banking with us.\nHave a nice day.',
        referenceDate: reference,
      );
      expect(result, isEmpty);
    });

    test('flags a transaction with no confident amount as needing review rather than guessing', () {
      final result = PasteTransactionExtractor.extract('05 Sep SWIGGY', referenceDate: reference);
      expect(result, hasLength(1));
      expect(result.first.amount, isNull);
      expect(result.first.hasRequiredFields, isFalse);
    });

    test('partial parsing keeps successfully-parsed rows even when others need review', () {
      final text = '05 Sep SWIGGY 420 DR\n06 Sep UNKNOWN MERCHANT\n07 Sep UBER 185.50 DR';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result, hasLength(3));
      expect(result.where((t) => t.hasRequiredFields), hasLength(2));
      expect(result.where((t) => !t.hasRequiredFields), hasLength(1));
    });
  });

  group('PasteTransactionExtractor — real-world Google Pay / PhonePe style copy text', () {
    test('extracts the reference number from "UPI transaction ID:" wording', () {
      final text = '₹420\nPaid to Swiggy Bangalore\n05 Sep 2026, 10:32 PM\n'
          'UPI transaction ID: 402812345678';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result, hasLength(1));
      expect(result.first.amount, 420.0);
      expect(result.first.date, DateTime(2026, 9, 5));
      expect(result.first.referenceNumber, '402812345678');
    });

    test('extracts the reference number from "Transaction ID" wording', () {
      final text = '₹1,299 Debited\nTo Amazon Pay India\n06 Sep 2026 09:15 AM\n'
          'Transaction ID T2609261234567890123';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result, hasLength(1));
      expect(result.first.referenceNumber, 'T2609261234567890123');
    });

    test('strips "Paid to" boilerplate and the timestamp out of the description, '
        'so the merchant key used for category suggestion is not polluted', () {
      final text = '₹420\nPaid to Swiggy Bangalore\n05 Sep 2026, 10:32 PM\n'
          'UPI transaction ID: 402812345678';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result.first.rawDescription, 'Swiggy Bangalore');
    });

    test('strips a bare leading "To "/"From " prefix (PhonePe-style) without '
        'truncating the merchant name', () {
      final text = '₹1,299 Debited\nTo Amazon Pay India\n06 Sep 2026 09:15 AM\n'
          'Transaction ID T2609261234567890123';
      final result = PasteTransactionExtractor.extract(text, referenceDate: reference);
      expect(result.first.rawDescription, 'Amazon Pay India');
    });

    test('does not strip "to"/"from" when they are not a leading connector', () {
      // Sanity check against over-stripping: a merchant name containing "to"
      // mid-string must survive untouched.
      final result = PasteTransactionExtractor.extract(
        '05 Sep TOTO CAFE 420 DR',
        referenceDate: reference,
      );
      expect(result.first.rawDescription, contains('Toto Cafe'));
    });
  });

  group('PasteTransactionExtractor — date/amount adjacency regression', () {
    test('does not misread an amount immediately after the date as a 3-digit year', () {
      // Regression: "06 Sep 420 DR" (amount right after the date, no
      // merchant in between) previously parsed "420" as the year, producing
      // the nonsense date 0420-09-06.
      final result = PasteTransactionExtractor.extract(
        '06 Sep 420 DR',
        referenceDate: reference,
      );
      expect(result, hasLength(1));
      expect(result.first.date, DateTime(2026, 9, 6));
      expect(result.first.date!.year, 2026);
      expect(result.first.amount, 420.0);
    });
  });

  test('extract returns an empty list for blank input', () {
    expect(PasteTransactionExtractor.extract('', referenceDate: reference), isEmpty);
  });
}
