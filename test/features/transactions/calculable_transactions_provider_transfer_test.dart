import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the Mobile↔Web parity audit's transfer
/// double-counting finding (2026-09-23): a transfer between two of the
/// user's own accounts, created on the web app via
/// `TransactionRepository.createTransferPair`, writes two ordinary
/// `transactions` documents (an `expense` leg and an `income` leg) sharing a
/// `transferId`. Before this fix, `calculableTransactionsProvider` had no
/// concept of `transferId` at all, so both legs passed straight through into
/// every Dashboard/Reports/Budget/Cash-Flow total — double-counting a pure
/// account-to-account move as both real income and a real expense.
void main() {
  late ProviderContainer container;
  late FakeFirebaseFirestore firestore;
  late String uid;

  setUp(() async {
    final auth = MockFirebaseAuth(signedIn: true);
    firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
    uid = auth.currentUser!.uid;
  });

  /// Writes a raw transaction document exactly as the web app's
  /// `transactionToFirestore` would — this app has no transfer-creation UI
  /// of its own, so the only way a `transferId` field reaches Firestore
  /// today is from the web app.
  Future<void> seedRawTransaction({
    required String id,
    required String type,
    required double amount,
    required String accountId,
    String? transferId,
  }) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .doc(id)
        .set({
          'type': type,
          'amount': amount,
          'dateTime': Timestamp.fromDate(DateTime(2026, 9, 1)),
          'accountId': accountId,
          'categoryId': 'cat-transfer',
          'description': 'Move to savings',
          'notes': '',
          'excludeFromCalculations': false,
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
          'transferId': transferId,
          'deletedAt': null,
        });
  }

  test(
    'calculableTransactionsProvider excludes both legs of a web-created transfer',
    () async {
      await seedRawTransaction(
        id: 'transfer-expense-leg',
        type: 'expense',
        amount: 2000,
        accountId: 'checking',
        transferId: 'transfer-1',
      );
      await seedRawTransaction(
        id: 'transfer-income-leg',
        type: 'income',
        amount: 2000,
        accountId: 'savings',
        transferId: 'transfer-1',
      );
      await seedRawTransaction(
        id: 'real-expense',
        type: 'expense',
        amount: 300,
        accountId: 'checking',
      );

      // Let transactionsStreamProvider pick up the seeded documents.
      await container.read(transactionsStreamProvider.future);

      final calculable = container.read(calculableTransactionsProvider);

      expect(calculable.map((t) => t.id), ['real-expense']);
      expect(
        calculable.fold<double>(0, (sum, t) => sum + t.signedAmount),
        -300,
        reason:
            'A pure transfer must never contribute to any balance/total — '
            'only the one real expense should count.',
      );
    },
  );
}
