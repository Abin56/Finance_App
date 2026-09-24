import 'package:finance_app/features/sms_inbox/domain/merchant/merchant_memory.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_identity_resolver.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/merchant_intelligence/upi_provider.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = MerchantIdentityResolver();

  MerchantMemory memory({
    required String merchantKey,
    TransactionType type = TransactionType.expense,
    String categoryId = 'cat-1',
  }) {
    return MerchantMemory(
      merchantKey: merchantKey,
      transactionType: type,
      categoryId: categoryId,
      timesUsed: 3,
      lastUsedAt: DateTime(2026, 7, 1),
    );
  }

  group('exact known merchant', () {
    test(
      'a VPA matching a known catalog entry resolves to its display name',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'swiggy@upi',
          smsBody: '₹850 paid to swiggy@upi',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.displayName, 'Swiggy');
        expect(identity.isKnown, isTrue);
        expect(identity.merchantType, MerchantType.knownBusiness);
        expect(identity.vpa?.raw, 'swiggy@upi');
      },
    );

    test('plain-text known merchant (no VPA) resolves via the catalog', () {
      final identity = resolver.resolve(
        regexMerchantGuess: 'NETFLIX',
        smsBody: 'Rs.649 debited towards NETFLIX subscription.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(identity.displayName, 'Netflix');
      expect(identity.merchantType, MerchantType.subscription);
      expect(identity.isKnown, isTrue);
    });
  });

  group('merchant alias', () {
    test('SWIGGY INSTAMART resolves distinctly from plain Swiggy', () {
      final instamart = resolver.resolve(
        regexMerchantGuess: 'SWIGGY INSTAMART',
        smsBody: 'Rs.450 paid to SWIGGY INSTAMART.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(instamart.displayName, 'Swiggy Instamart');

      final plain = resolver.resolve(
        regexMerchantGuess: 'SWIGGY',
        smsBody: 'Rs.450 paid to SWIGGY.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(plain.displayName, 'Swiggy');
      expect(plain.normalizedName, isNot(instamart.normalizedName));
    });
  });

  group('unknown VPA / phone-number VPA', () {
    test('an unrecognized VPA stays unknown, keeping the VPA as evidence', () {
      final identity = resolver.resolve(
        regexMerchantGuess: 'merchant123@upi',
        smsBody: 'Rs.500 sent to merchant123@upi.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(identity.displayName, isNull);
      expect(identity.isKnown, isFalse);
      expect(identity.vpa?.raw, 'merchant123@upi');
    });

    test('a phone-number VPA never becomes a person\'s name', () {
      final identity = resolver.resolve(
        regexMerchantGuess: '9876543210@oksbi',
        smsBody: 'Rs.450 transferred to 9876543210@oksbi',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(
        identity.displayName,
        isNull,
        reason: 'must never invent a name like "Rahul"',
      );
      expect(identity.merchantType, MerchantType.unknown);
      expect(identity.vpa?.localPartIsPhoneNumber, isTrue);
      expect(identity.vpa?.raw, '9876543210@oksbi');
    });
  });

  group('user history overriding an unrecognized business', () {
    test(
      'a local shop the user has transacted with before is user-confirmed',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'Ramesh Stores',
          smsBody: 'Rs.300 paid to Ramesh Stores.',
          memories: [memory(merchantKey: 'ramesh stores')],
          transactionType: TransactionType.expense,
        );
        expect(identity.isUserConfirmed, isTrue);
        expect(identity.isKnown, isTrue);
        expect(identity.displayName, 'Ramesh Stores');
      },
    );

    test(
      'with no history, the same shop stays unrecognized (not user-confirmed)',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'Ramesh Stores',
          smsBody: 'Rs.300 paid to Ramesh Stores.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.isUserConfirmed, isFalse);
        expect(identity.merchantType, MerchantType.unknownBusiness);
      },
    );
  });

  group('payment provider vs merchant', () {
    test(
      'PhonePe mentioned as the payment rail is never treated as the merchant',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'swiggy@upi',
          smsBody: 'Payment of Rs.240 to Zomato via PhonePe. VPA swiggy@upi.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.paymentProvider, UpiProvider.phonePe);
        expect(identity.displayName, isNot('PhonePe'));
      },
    );

    test(
      'a bare provider name standing in for the merchant is recognized as such',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'Paytm',
          smsBody: 'Rs.500 paid using Paytm.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.merchantType, MerchantType.paymentProvider);
        expect(identity.displayName, isNull);
      },
    );

    test(
      'Google Pay used to pay a real store resolves the store as the merchant',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'ABC Store',
          smsBody: 'Paid using Google Pay to ABC Store.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.paymentProvider, UpiProvider.googlePay);
        expect(identity.displayName, 'ABC Store');
        expect(identity.merchantType, isNot(MerchantType.paymentProvider));
      },
    );
  });

  group('local / unknown businesses', () {
    test(
      'an unrecognized business name is kept verbatim, never invented further',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'ABC Bakery',
          smsBody: 'Rs.200 paid to ABC Bakery.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.displayName, 'ABC Bakery');
        expect(identity.isKnown, isFalse);
        expect(identity.merchantType, MerchantType.unknownBusiness);
      },
    );
  });

  group('individual vs business heuristic', () {
    test('a plain personal name is flagged individual, not a business', () {
      final identity = resolver.resolve(
        regexMerchantGuess: 'Rohit Kumar',
        smsBody: 'You paid Rs.120 to Rohit Kumar using Google Pay.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(identity.merchantType, MerchantType.individual);
      expect(identity.displayName, 'Rohit Kumar');
    });

    test('a name with a business suffix is not flagged individual', () {
      final identity = resolver.resolve(
        regexMerchantGuess: 'Ramesh Traders',
        smsBody: 'Rs.500 paid to Ramesh Traders.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(identity.merchantType, isNot(MerchantType.individual));
    });
  });

  group('Amazon / Google / Apple variants stay distinct', () {
    test('Amazon Prime is a subscription, not generic shopping', () {
      final identity = resolver.resolve(
        regexMerchantGuess: 'Amazon Prime',
        smsBody: 'Rs.1499 debited for Amazon Prime membership renewal.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(identity.merchantType, MerchantType.subscription);
      expect(identity.categoryIsAmbiguous, isFalse);
    });

    test(
      'bare Amazon is flagged category-ambiguous even though the merchant is known',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'Amazon',
          smsBody: 'Rs.500 paid to Amazon.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.isKnown, isTrue);
        expect(identity.categoryIsAmbiguous, isTrue);
      },
    );

    test(
      'Google Pay is never a catalog merchant (it is a payment provider)',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: 'Google Pay',
          smsBody: 'Paid via Google Pay.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.merchantType, MerchantType.paymentProvider);
      },
    );

    test('Apple Music is a subscription; bare Apple is ambiguous', () {
      final music = resolver.resolve(
        regexMerchantGuess: 'Apple Music',
        smsBody: 'Rs.99 debited for Apple Music.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(music.merchantType, MerchantType.subscription);

      final bare = resolver.resolve(
        regexMerchantGuess: 'Apple',
        smsBody: 'Rs.99 debited for Apple.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(bare.categoryIsAmbiguous, isTrue);
    });
  });

  group('no signal at all', () {
    test(
      'null merchant guess with no VPA in the body resolves fully unknown',
      () {
        final identity = resolver.resolve(
          regexMerchantGuess: null,
          smsBody: 'Rs.500 debited from a/c XX1234 on 15-07-26.',
          memories: const [],
          transactionType: TransactionType.expense,
        );
        expect(identity.displayName, isNull);
        expect(identity.merchantType, MerchantType.unknown);
        expect(identity.isKnown, isFalse);
      },
    );

    test('an all-noise merchant guess (e.g. bare "UPI") resolves unknown', () {
      final identity = resolver.resolve(
        regexMerchantGuess: 'UPI',
        smsBody: 'Rs.500 debited via UPI.',
        memories: const [],
        transactionType: TransactionType.expense,
      );
      expect(identity.merchantType, MerchantType.unknown);
    });
  });
}
