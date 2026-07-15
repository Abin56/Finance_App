import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MerchantKey.normalize', () {
    test('collapses casing, punctuation and rail noise to one key', () {
      // All three are how different banks render the same merchant. If these
      // don't collapse, the memory never recalls what the user taught it.
      expect(MerchantKey.normalize('SWIGGY'), 'swiggy');
      expect(MerchantKey.normalize('Swiggy Ltd'), 'swiggy');
      expect(MerchantKey.normalize('UPI-SWIGGY*ORDER'), 'swiggy order');
    });

    test('strips terminal ids that are pure digits', () {
      expect(MerchantKey.normalize('POS 123456 SWIGGY'), 'swiggy');
    });

    test('keeps genuinely different merchants apart', () {
      // Over-merging is worse than not matching: it would confidently suggest
      // the wrong category for a real, different merchant.
      expect(MerchantKey.normalize('AMAZON'), isNot(MerchantKey.normalize('AMAZON FRESH')));
    });

    test('returns null when nothing identifying survives', () {
      // An empty key must never be stored, or every unidentifiable merchant
      // would share one bucket and recall each other's categories.
      expect(MerchantKey.normalize(null), isNull);
      expect(MerchantKey.normalize('   '), isNull);
      expect(MerchantKey.normalize('*** 99999 ***'), isNull);
      expect(MerchantKey.normalize('UPI'), isNull);
    });
  });
}
