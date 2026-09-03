import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_identity.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_identity_cache.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const swiggy = MerchantIdentity(
    isKnown: true,
    source: MerchantSource.vpaCatalog,
    confidence: 0.85,
    displayName: 'Swiggy',
  );

  test('a miss returns null', () {
    final cache = MerchantIdentityCache();
    expect(cache.get(merchantText: 'swiggy@upi'), isNull);
  });

  test('put then get by the same VPA returns the cached identity', () {
    final cache = MerchantIdentityCache();
    cache.put(swiggy, vpaRaw: 'swiggy@upi');
    expect(cache.get(vpaRaw: 'swiggy@upi')?.displayName, 'Swiggy');
  });

  test(
    'put then get by the same merchant text returns the cached identity',
    () {
      final cache = MerchantIdentityCache();
      cache.put(swiggy, merchantText: 'SWIGGY');
      expect(
        cache.get(merchantText: 'swiggy')?.displayName,
        'Swiggy',
        reason: 'lookup is normalized, case-insensitive',
      );
    },
  );

  test('different merchants never collide', () {
    const zomato = MerchantIdentity(
      isKnown: true,
      source: MerchantSource.vpaCatalog,
      confidence: 0.85,
      displayName: 'Zomato',
    );
    final cache = MerchantIdentityCache();
    cache.put(swiggy, merchantText: 'Swiggy');
    cache.put(zomato, merchantText: 'Zomato');
    expect(cache.get(merchantText: 'Swiggy')?.displayName, 'Swiggy');
    expect(cache.get(merchantText: 'Zomato')?.displayName, 'Zomato');
  });

  test(
    'a cache with nothing put for null/empty inputs never throws and always misses',
    () {
      final cache = MerchantIdentityCache();
      expect(cache.get(merchantText: null), isNull);
      expect(cache.get(merchantText: ''), isNull);
    },
  );
}
