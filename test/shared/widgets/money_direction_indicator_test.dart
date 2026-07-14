import 'package:finance_app/shared/widgets/states/money_direction_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoneyDirectionX.forSignedBalance', () {
    test('positive balance is toReceive', () {
      expect(MoneyDirectionX.forSignedBalance(100), MoneyDirection.toReceive);
    });

    test('negative balance is toPay', () {
      expect(MoneyDirectionX.forSignedBalance(-50), MoneyDirection.toPay);
    });

    test('zero balance is null (caller treats as completed)', () {
      expect(MoneyDirectionX.forSignedBalance(0), isNull);
    });
  });

  group('MoneyDirection labels', () {
    test('each direction has the expected plain-language label', () {
      expect(MoneyDirection.toReceive.label, 'To Receive');
      expect(MoneyDirection.toPay.label, 'To Pay');
      expect(MoneyDirection.partial.label, 'Partly Paid');
      expect(MoneyDirection.completed.label, 'Paid');
    });
  });
}
