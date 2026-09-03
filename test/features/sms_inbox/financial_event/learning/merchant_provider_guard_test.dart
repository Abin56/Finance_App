import 'package:finance_app/features/sms_inbox/domain/learning/merchant_learning_profile.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_learning_store.dart';
import 'package:finance_app/features/sms_inbox/domain/learning/merchant_provider_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MerchantProviderGuard', () {
    test('flags known payment providers by name', () {
      expect(MerchantProviderGuard.isProviderName('PhonePe'), isTrue);
      expect(MerchantProviderGuard.isProviderName('Google Pay'), isTrue);
      expect(MerchantProviderGuard.isProviderName('GPay'), isTrue);
      expect(MerchantProviderGuard.isProviderName('BHIM'), isTrue);
      expect(MerchantProviderGuard.isProviderName('CRED'), isTrue);
    });

    test('does not flag a real merchant', () {
      expect(MerchantProviderGuard.isProviderName('Swiggy'), isFalse);
      expect(MerchantProviderGuard.isProviderName('Amazon'), isFalse);
    });
  });

  group('MerchantLearningStore', () {
    test('refuses to store a profile keyed by a payment provider', () {
      final store = MerchantLearningStore();
      final providerKey = MerchantProviderGuard.isProviderName('PhonePe');
      expect(providerKey, isTrue);

      expect(
        () => store.put(
          const MerchantLearningProfile(userId: 'u1', merchantKey: 'phonepe'),
        ),
        throwsArgumentError,
      );
    });

    test('accepts and retrieves a real merchant profile', () {
      final store = MerchantLearningStore();
      const profile = MerchantLearningProfile(userId: 'u1', merchantKey: 'swiggy');
      store.put(profile);

      expect(store.get('u1', 'swiggy'), same(profile));
    });
  });
}
