import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
  });

  test('netWorthProvider sums currentBalance across every account', () async {
    final accounts = container.read(accountRepositoryProvider);
    await accounts.createAccount(name: 'Wallet', type: AccountType.cash, openingBalance: 1000, colorValue: 0xFF000000);
    await accounts.createAccount(name: 'Bank', type: AccountType.bank, openingBalance: 5000, colorValue: 0xFF000000);
    await accounts.createAccount(name: 'Credit line', type: AccountType.card, openingBalance: -800, colorValue: 0xFF000000);

    await container.read(accountsStreamProvider.future);

    expect(container.read(netWorthProvider), 5200);
  });

  test('netWorthProvider is 0 with no accounts', () async {
    expect(container.read(netWorthProvider), 0);
  });
}
