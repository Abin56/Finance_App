import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('merchant alias normalization for learning', () {
    test('Swiggy, SWIGGY, and Swiggy Pvt Ltd collapse to the same key', () {
      final a = MerchantKey.normalize('Swiggy');
      final b = MerchantKey.normalize('SWIGGY');
      final c = MerchantKey.normalize('Swiggy Pvt Ltd');

      expect(a, equals(b));
      expect(a, equals(c));
    });

    test('Swiggy Instamart stays a distinct key from plain Swiggy', () {
      final swiggy = MerchantKey.normalize('Swiggy');
      final instamart = MerchantKey.normalize('Swiggy Instamart');

      expect(instamart, isNot(equals(swiggy)));
    });
  });
}
