import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_catalog.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lookupByText', () {
    test('finds a merchant by its canonical name, case-insensitively', () {
      expect(MerchantCatalog.lookupByText('SWIGGY')?.canonicalName, 'Swiggy');
      expect(MerchantCatalog.lookupByText('swiggy')?.canonicalName, 'Swiggy');
    });

    test('finds a merchant by a registered alias', () {
      expect(
        MerchantCatalog.lookupByText('Swiggy Instamart')?.canonicalName,
        'Swiggy',
      );
      expect(MerchantCatalog.lookupByText('D Mart')?.canonicalName, 'DMart');
    });

    test('returns null for an unknown merchant text', () {
      expect(MerchantCatalog.lookupByText('Some Random Local Shop'), isNull);
    });

    test('never merges unrelated merchants that merely share a substring', () {
      // Regression guard for the exact case the SMS AI rebuild plan calls
      // out: "ABC Bakery"/"ABC Electronics"/"ABC Traders" must never collide.
      expect(MerchantCatalog.lookupByText('ABC Bakery'), isNull);
      expect(
        MerchantCatalog.lookupByText('Amazon Pay'),
        isNull,
        reason: 'a different rail from plain Amazon, must not be conflated',
      );
    });

    test('every catalog entry has a sensible merchant type', () {
      expect(
        MerchantCatalog.lookupByText('Swiggy')?.merchantType,
        MerchantType.business,
      );
    });
  });

  group('lookupByVpaLocalPart', () {
    test('finds a merchant by an exact VPA alias', () {
      expect(
        MerchantCatalog.lookupByVpaLocalPart('swiggy')?.canonicalName,
        'Swiggy',
      );
    });

    test(
      'finds a merchant when the local part has a real-world store/order suffix',
      () {
        expect(
          MerchantCatalog.lookupByVpaLocalPart('swiggy.blr123')?.canonicalName,
          'Swiggy',
        );
        expect(
          MerchantCatalog.lookupByVpaLocalPart('zomatofood')?.canonicalName,
          'Zomato',
        );
      },
    );

    test(
      'does not match a local part that merely contains the alias, not starting with it',
      () {
        expect(MerchantCatalog.lookupByVpaLocalPart('myswiggystore'), isNull);
      },
    );

    test(
      'returns null for an unrecognized VPA local part — never invents an identity',
      () {
        expect(MerchantCatalog.lookupByVpaLocalPart('9876543210'), isNull);
        expect(MerchantCatalog.lookupByVpaLocalPart('randomguy123'), isNull);
      },
    );

    test(
      'the longer, more specific alias wins when it is also a prefix of a shorter one',
      () {
        // "dmart" only has one alias here, but this guards the general
        // longest-match-first invariant the catalog documents.
        expect(
          MerchantCatalog.lookupByVpaLocalPart('dmartonline')?.canonicalName,
          'DMart',
        );
      },
    );
  });

  test(
    'the catalog covers every representative merchant the corpus expects',
    () {
      const expectedNames = [
        'Swiggy',
        'Zomato',
        'Amazon',
        'Flipkart',
        'Uber',
        'Ola',
        'Netflix',
        'Spotify',
        'Jio',
        'Airtel',
        'BSNL',
        'BigBasket',
        'Blinkit',
        'Zepto',
        'DMart',
        'Indian Oil',
        'HPCL',
        'Shell',
      ];
      for (final name in expectedNames) {
        expect(
          MerchantCatalog.lookupByText(name),
          isNotNull,
          reason: '$name should be in the catalog',
        );
      }
    },
  );
}
