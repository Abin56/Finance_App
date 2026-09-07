import 'package:finance_app/features/smart_import/domain/smart_import_amount_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartImportAmountParser', () {
    test('parses a plain rupee amount', () {
      final result = SmartImportAmountParser.extractFirst('₹420');
      expect(result?.value, 420.0);
      expect(result?.hadCurrencyMarker, isTrue);
    });

    test('parses a comma-grouped amount with no decimal', () {
      final result = SmartImportAmountParser.extractFirst('₹1,299');
      expect(result?.value, 1299.0);
    });

    test('parses a comma-grouped amount with paise', () {
      final result = SmartImportAmountParser.extractFirst('₹1,299.00');
      expect(result?.value, 1299.0);
    });

    test('parses a bare decimal amount with no currency marker', () {
      final result = SmartImportAmountParser.extractFirst('185.50');
      expect(result?.value, 185.50);
      expect(result?.hadCurrencyMarker, isFalse);
    });

    test('parses a bare comma-grouped decimal amount', () {
      final result = SmartImportAmountParser.extractFirst('1,299.00');
      expect(result?.value, 1299.0);
    });

    test('tolerates a space between the currency symbol and the digits', () {
      final result = SmartImportAmountParser.extractFirst('₹ 420');
      expect(result?.value, 420.0);
    });

    test('handles Rs. and INR markers', () {
      expect(SmartImportAmountParser.extractFirst('Rs. 420')?.value, 420.0);
      expect(SmartImportAmountParser.extractFirst('INR 420')?.value, 420.0);
    });

    test('corrects an OCR-confused O for a 0', () {
      final result = SmartImportAmountParser.extractFirst('₹42O');
      expect(result?.value, 420.0);
    });

    test('corrects an OCR-confused S for a 5', () {
      final result = SmartImportAmountParser.extractFirst('₹1,29S');
      expect(result?.value, 1295.0);
    });

    test(
      'prefers a currency-marked amount over a bare number on the same line',
      () {
        final result = SmartImportAmountParser.extractFirst(
          'Ref 12345 ₹420.00',
        );
        expect(result?.value, 420.0);
        expect(result?.hadCurrencyMarker, isTrue);
      },
    );

    test('ignores a trailing "/-" (common Indian rupee notation)', () {
      final result = SmartImportAmountParser.extractFirst('₹420/-');
      expect(result?.value, 420.0);
    });

    test('does not treat a bare integer with no decimal as an amount', () {
      // A lone "05" (e.g. a day-of-month) must never be mistaken for money.
      expect(SmartImportAmountParser.extractFirst('05'), isNull);
    });

    test('returns null when no plausible amount is present', () {
      expect(SmartImportAmountParser.extractFirst('SWIGGY'), isNull);
    });

    test('rejects a zero amount', () {
      expect(SmartImportAmountParser.extractFirst('₹0'), isNull);
    });
  });
}
