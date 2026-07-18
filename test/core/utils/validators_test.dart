import 'package:finance_app/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.amountUpTo', () {
    test('accepts an amount exactly equal to the remaining balance', () {
      expect(Validators.amountUpTo(4250)('4250'), isNull);
    });

    test('accepts an amount less than the remaining balance', () {
      expect(Validators.amountUpTo(4250)('2000'), isNull);
    });

    test('rejects an amount greater than the remaining balance', () {
      expect(Validators.amountUpTo(4250)('4251'), 'Payment amount cannot exceed the remaining balance.');
    });

    test('rejects a much larger overpayment', () {
      expect(Validators.amountUpTo(4250)('10000'), 'Payment amount cannot exceed the remaining balance.');
    });

    test('rejects zero', () {
      expect(Validators.amountUpTo(4250)('0'), isNotNull);
    });

    test('rejects a negative amount', () {
      expect(Validators.amountUpTo(4250)('-100'), isNotNull);
    });

    test('rejects blank input', () {
      expect(Validators.amountUpTo(4250)(''), isNotNull);
      expect(Validators.amountUpTo(4250)(null), isNotNull);
    });

    test('rejects non-numeric input', () {
      expect(Validators.amountUpTo(4250)('abc'), isNotNull);
    });

    test('accepts a decimal amount within bounds', () {
      expect(Validators.amountUpTo(4250.50)('4250.50'), isNull);
      expect(Validators.amountUpTo(4250.50)('4250.49'), isNull);
    });

    test('rejects a decimal amount that exceeds the remaining balance by a fraction', () {
      expect(Validators.amountUpTo(4250)('4250.01'), 'Payment amount cannot exceed the remaining balance.');
    });
  });
}
