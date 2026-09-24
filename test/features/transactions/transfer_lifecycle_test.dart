import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/constants/firestore_constants.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end verification of the transfer double-counting fix across the
/// full lifecycle a web-created transfer pair goes through once this app
/// reads it: read both legs, exclude both from every calculation, keep
/// account balances reflecting the real money movement, survive a mobile
/// edit without losing `transferId`, and survive soft-delete/restore of one
/// leg without silently double-counting the surviving leg.
///
/// This app has no transfer-creation UI of its own (see `Transaction.
/// transferId`'s doc comment), so the pair is seeded directly into Firestore
/// exactly as `TransactionRepository.createTransferPair` (flowfi-web) would
/// write it — two `transactions` documents sharing one `transferId`, plus
/// the matching balance deltas on each account — rather than routed through
/// this app's own `createTransaction`, which has no `transferId` parameter.
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

  CollectionReference<Map<String, dynamic>> rawTransactions() => firestore
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.transactions);

  /// Seeds one leg exactly as web's `transactionToFirestore` would write it.
  Future<void> seedLeg({
    required String id,
    required String type,
    required String accountId,
    required String transferId,
  }) async {
    await rawTransactions().doc(id).set({
      'type': type,
      'amount': 2000.0,
      'dateTime': Timestamp.fromDate(DateTime(2026, 9, 1)),
      'accountId': accountId,
      'categoryId': 'cat-transfer',
      'description': 'Move to savings',
      'notes': '',
      'excludeFromCalculations': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
      'transferId': transferId,
      'deletedAt': null,
      'editHistory': <Map<String, dynamic>>[],
    });
  }

  test(
    'full transfer lifecycle: read, exclude, balance, edit, delete, restore',
    () async {
      final accountRepo = container.read(accountRepositoryProvider);
      final checking = await accountRepo.createAccount(
        name: 'Checking',
        type: AccountType.bank,
        openingBalance: 10000,
        colorValue: 0xFF000000,
      );
      final savings = await accountRepo.createAccount(
        name: 'Savings',
        type: AccountType.bank,
        openingBalance: 5000,
        colorValue: 0xFF000000,
      );

      const transferId = 'transfer-1';
      await seedLeg(
        id: 'expense-leg',
        type: 'expense',
        accountId: checking.id,
        transferId: transferId,
      );
      await seedLeg(
        id: 'income-leg',
        type: 'income',
        accountId: savings.id,
        transferId: transferId,
      );
      // Mirrors createTransferPair's own atomic balance adjustment on each leg's account.
      final checkingFresh = (await accountRepo.getByKey(checking.id))!;
      await accountRepo.adjustBalance(checkingFresh, -2000);
      final savingsFresh = (await accountRepo.getByKey(savings.id))!;
      await accountRepo.adjustBalance(savingsFresh, 2000);

      // --- 1. Mobile reads both legs ---
      var allTransactions = await container.read(
        transactionsStreamProvider.future,
      );
      expect(allTransactions.map((t) => t.id).toSet(), {
        'expense-leg',
        'income-leg',
      });
      expect(allTransactions.every((t) => t.transferId == transferId), isTrue);

      // --- 2. Dashboard/calculations exclude both legs ---
      var calculable = container.read(calculableTransactionsProvider);
      expect(calculable, isEmpty);

      // --- 3. Account balances still reflect the actual money movement ---
      expect((await accountRepo.getByKey(checking.id))?.currentBalance, 8000);
      expect((await accountRepo.getByKey(savings.id))?.currentBalance, 7000);

      // --- 4. Mobile edits a transfer-tagged transaction without removing transferId ---
      final txnRepo = container.read(transactionRepositoryProvider);
      final expenseLeg = allTransactions.firstWhere((t) => t.id == 'expense-leg');
      await txnRepo.editTransaction(expenseLeg, notes: 'Edited on mobile');

      allTransactions = await container.read(transactionsStreamProvider.future);
      final editedLeg = allTransactions.firstWhere((t) => t.id == 'expense-leg');
      expect(editedLeg.notes, 'Edited on mobile');
      expect(
        editedLeg.transferId,
        transferId,
        reason: 'editing an unrelated field must not wipe transferId',
      );
      calculable = container.read(calculableTransactionsProvider);
      expect(
        calculable,
        isEmpty,
        reason: 'the edited leg must still be excluded from calculations',
      );

      // --- 5. Transfer delete/restore behavior ---
      final incomeLeg = allTransactions.firstWhere((t) => t.id == 'income-leg');
      await txnRepo.softDeleteTransaction(editedLeg);
      // fake_cloud_firestore's `_DummyTransaction.set()` (used internally by
      // softDeleteTransaction/restoreTransaction/editTransaction/
      // createTransaction now that they're atomic — see
      // TransactionRepository's class doc comment) calls
      // `documentReference.set(data)` without awaiting it, so the write can
      // still be in flight when `runTransaction()`'s own Future resolves —
      // a real Firestore transaction's Future only resolves once every
      // write in it is durably committed, but this fake's transaction
      // support doesn't honor that. `watchAll()`'s `.snapshots()`-backed
      // stream can therefore observe a stale snapshot for one more event
      // loop turn than a direct `.get()` (e.g. `accountRepo.getByKey`
      // above, which is unaffected). Same class of fake-only gap as
      // `account_repository_test.dart`'s documented "KNOWN TEST-HARNESS
      // LIMITATION" — flushing one macrotask turn here is enough for the
      // fake's pending write to land before the stream is read.
      await Future<void>.delayed(Duration.zero);

      // The deleted leg's own account balance is reversed...
      expect((await accountRepo.getByKey(checking.id))?.currentBalance, 10000);
      // ...but the sibling leg's account is untouched by a single-leg delete
      // (this app has no `deleteTransferPair` — mobile has no transfer-pair
      // awareness beyond exclusion/round-tripping — see final report).
      expect((await accountRepo.getByKey(savings.id))?.currentBalance, 7000);

      allTransactions = await container.read(transactionsStreamProvider.future);
      expect(
        allTransactions.map((t) => t.id),
        ['income-leg'],
        reason: 'the deleted leg drops out of the active stream',
      );
      calculable = container.read(calculableTransactionsProvider);
      expect(
        calculable,
        isEmpty,
        reason:
            'the surviving leg must still be excluded — no duplicate income '
            'appears just because its sibling was deleted',
      );

      final trash = await container.read(transactionsTrashStreamProvider.future);
      expect(trash.map((t) => t.id), ['expense-leg']);
      expect(trash.single.transferId, transferId);

      // Restore it.
      final trashedLeg = trash.single;
      await txnRepo.restoreTransaction(trashedLeg);
      await Future<void>.delayed(Duration.zero); // see comment above

      expect((await accountRepo.getByKey(checking.id))?.currentBalance, 8000);
      allTransactions = await container.read(transactionsStreamProvider.future);
      expect(allTransactions.map((t) => t.id).toSet(), {
        'expense-leg',
        'income-leg',
      });
      expect(
        allTransactions.every((t) => t.transferId == transferId),
        isTrue,
        reason: 'transferId survives a full delete/restore round trip',
      );
      calculable = container.read(calculableTransactionsProvider);
      expect(
        calculable,
        isEmpty,
        reason:
            'no duplicate income/expense appears anywhere in the '
            'calculation boundary after the full lifecycle',
      );
      expect(incomeLeg.transferId, transferId); // sanity: never mutated
    },
  );
}
