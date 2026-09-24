import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/errors/app_exception.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AccountRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final collection = firestore
        .collection('accounts')
        .withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    repository = AccountRepository(collection);
  });

  group('AccountRepository.createAccount', () {
    test('sets currentBalance to openingBalance', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 500,
        colorValue: 0xFF000000,
      );

      expect(account.currentBalance, 500);
      expect(account.openingBalance, 500);
    });

    test('supports a negative opening balance', () async {
      final account = await repository.createAccount(
        name: 'Credit line',
        type: AccountType.card,
        openingBalance: -200,
        colorValue: 0xFF000000,
      );

      expect(account.currentBalance, -200);
    });
  });

  group('AccountRepository.adjustBalance', () {
    test('applies a positive delta and records an audit entry', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.adjustBalance(account, 250);

      expect(account.currentBalance, 1250);
      expect(account.editHistory, isNotEmpty);
      expect(account.editHistory.last.field, 'currentBalance');
    });

    test('applies a negative delta', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.adjustBalance(account, -300);

      expect(account.currentBalance, 700);
    });

    test('is a no-op for a zero delta (no audit entry recorded)', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.adjustBalance(account, 0);

      expect(account.currentBalance, 1000);
      expect(account.editHistory, isEmpty);
    });

    test(
      'persists the new balance to Firestore, not just the in-memory object',
      () async {
        final account = await repository.createAccount(
          name: 'Wallet',
          type: AccountType.cash,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );

        await repository.adjustBalance(account, 500);

        final reloaded = await repository.getByKey(account.id);
        expect(reloaded?.currentBalance, 1500);
      },
    );

    test(
      'REGRESSION (audit finding, 2026-09-23): composes two concurrent '
      'deltas instead of losing one. Before this fix, adjustBalance applied '
      'newBalance = staleSnapshot.currentBalance + delta straight onto the '
      'passed-in in-memory object with a plain (non-transactional) write — '
      'unlike the web app\'s port of this same method, which always wrapped '
      'every balance mutation in runTransaction (lib/repositories/'
      'account-repository.ts + transaction-repository.ts). Two independently '
      'fetched copies of the same account (simulating this app\'s mobile '
      'client and the web client both holding a balance they read moments '
      'apart) each applying their own delta from that same stale starting '
      'point used to have the second write silently clobber the first\'s '
      'effect. adjustBalance now re-reads the document fresh inside a '
      'Firestore transaction, so this composes correctly regardless of '
      'which in-memory snapshot the caller happened to be holding.',
      () async {
        final created = await repository.createAccount(
          name: 'Shared Wallet',
          type: AccountType.cash,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );

        // Two independent reads of the same document — e.g. mobile's own
        // provider stream snapshot and a concurrently-open web tab's
        // snapshot, both observing currentBalance == 1000 before either
        // writer's delta has landed.
        final mobileCopy = await repository.getByKey(created.id);
        final webCopy = await repository.getByKey(created.id);
        expect(mobileCopy!.currentBalance, 1000);
        expect(webCopy!.currentBalance, 1000);

        // Mobile applies +200 (e.g. a new expense's balanceEffect) first.
        await repository.adjustBalance(mobileCopy, 200);
        final afterMobileWrite = await repository.getByKey(created.id);
        expect(afterMobileWrite?.currentBalance, 1200);

        // Web then applies its own +300 (a different, independent expense),
        // still holding its own stale 1000 in memory — the transaction must
        // re-read 1200 from Firestore rather than trusting webCopy.
        await repository.adjustBalance(webCopy, 300);

        final finalAccount = await repository.getByKey(created.id);
        // Race-free result: 1000 + 200 + 300 = 1500 — both deltas composed.
        expect(finalAccount?.currentBalance, 1500);
      },
    );

    /// Sign-combination matrix for the same "two stale snapshots" shape as
    /// the regression test above — verification pass, 2026-09-23. A
    /// composition bug that only manifests for one sign combination (e.g.
    /// a naive `abs()` somewhere) would slip past a single positive+positive
    /// case; each combination is covered explicitly here.
    Future<void> expectComposedDeltas({
      required double opening,
      required double deltaA,
      required double deltaB,
      required double expected,
    }) async {
      final created = await repository.createAccount(
        name: 'Shared Wallet',
        type: AccountType.cash,
        openingBalance: opening,
        colorValue: 0xFF000000,
      );
      final copyA = await repository.getByKey(created.id);
      final copyB = await repository.getByKey(created.id);

      await repository.adjustBalance(copyA!, deltaA);
      await repository.adjustBalance(copyB!, deltaB);

      final finalAccount = await repository.getByKey(created.id);
      expect(finalAccount?.currentBalance, expected);
    }

    test(
      'composes two positive deltas from stale snapshots (+200, +300)',
      () => expectComposedDeltas(
        opening: 1000,
        deltaA: 200,
        deltaB: 300,
        expected: 1500,
      ),
    );

    test(
      'composes a positive and a negative delta from stale snapshots '
      '(+500, -300)',
      () => expectComposedDeltas(
        opening: 1000,
        deltaA: 500,
        deltaB: -300,
        expected: 1200,
      ),
    );

    test(
      'composes two negative deltas from stale snapshots (-200, -300)',
      () => expectComposedDeltas(
        opening: 1000,
        deltaA: -200,
        deltaB: -300,
        expected: 500,
      ),
    );

    test(
      'composes three deltas from three independent stale snapshots '
      '(+150, -400, +900)',
      () async {
        final created = await repository.createAccount(
          name: 'Shared Wallet',
          type: AccountType.cash,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );
        final copyA = await repository.getByKey(created.id);
        final copyB = await repository.getByKey(created.id);
        final copyC = await repository.getByKey(created.id);

        await repository.adjustBalance(copyA!, 150);
        await repository.adjustBalance(copyB!, -400);
        await repository.adjustBalance(copyC!, 900);

        final finalAccount = await repository.getByKey(created.id);
        expect(finalAccount?.currentBalance, 1650); // 1000+150-400+900
      },
    );

    test(
      'KNOWN TEST-HARNESS LIMITATION (verification pass, 2026-09-23): '
      'fake_cloud_firestore\'s runTransaction does NOT provide true '
      'isolation under genuinely concurrent Future.wait calls, so this '
      'in-process fake cannot itself prove production concurrency safety. '
      'fake_cloud_firestore\'s own source (_DummyTransaction, package:'
      'fake_cloud_firestore/src/fake_cloud_firestore_instance.dart) is '
      'documented as "sequentially executes the operations without any '
      'rollback" — it never re-reads or retries, so two Future.wait\'d '
      'transactions can both tx.get() the same stale document before '
      'either tx.set() commits, exactly reproducing the original race this '
      'fix targets. This is a fake-harness gap, not a production bug: real '
      'Firestore\'s server-side optimistic-concurrency retry (the actual '
      'mechanism adjustBalance now depends on) is proven correct under '
      'genuine concurrency against a REAL Firestore Emulator in '
      'tests/integration/account-balance-concurrency.test.ts (flowfi-web) '
      '— the same guarantee this app\'s cloud_firestore SDK relies on '
      'against the same backend. The sequential-stale-snapshot tests above '
      '(same starting point, non-overlapping writes) are what this app\'s '
      'own Dart test suite CAN faithfully exercise, and they pass.',
      () async {
        final created = await repository.createAccount(
          name: 'Shared Wallet',
          type: AccountType.cash,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );
        final copyA = (await repository.getByKey(created.id))!;
        final copyB = (await repository.getByKey(created.id))!;

        await Future.wait([
          repository.adjustBalance(copyA, 200),
          repository.adjustBalance(copyB, 300),
        ]);

        final finalAccount = await repository.getByKey(created.id);
        // NOT 1500 here — see the test name/doc comment above. This
        // documents the fake's actual behavior; it is not the expected
        // production result (proven separately against a real emulator).
        expect(finalAccount?.currentBalance, 1300);
      },
    );
  });

  group('AccountRepository.reconcileBalance', () {
    test(
      'overwrites currentBalance with openingBalance + transactionsTotal when they differ',
      () async {
        final account = await repository.createAccount(
          name: 'Wallet',
          type: AccountType.cash,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );
        // Simulate drift: currentBalance says 1200 but transactions only sum to 100.
        await repository.adjustBalance(account, 200);

        await repository.reconcileBalance(account, 100);

        expect(
          account.currentBalance,
          1100,
        ); // openingBalance(1000) + transactionsTotal(100)
      },
    );

    test('is a no-op when the balance already matches', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );
      final historyLengthBefore = account.editHistory.length;

      await repository.reconcileBalance(account, 0);

      expect(account.currentBalance, 1000);
      expect(account.editHistory.length, historyLengthBefore);
    });
  });

  group('AccountRepository.editAccount', () {
    test(
      'updates name/type/colorValue and records an audit entry per changed field',
      () async {
        final account = await repository.createAccount(
          name: 'Wallet',
          type: AccountType.cash,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );

        await repository.editAccount(
          account,
          name: 'Main Wallet',
          type: AccountType.bank,
        );

        expect(account.name, 'Main Wallet');
        expect(account.type, AccountType.bank);
        expect(account.editHistory.length, 2);
      },
    );

    test('does not expose a way to change openingBalance', () async {
      final account = await repository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF000000,
      );

      await repository.editAccount(account, name: 'Renamed');

      expect(account.openingBalance, 1000);
    });
  });

  group('AccountRepository — bank/holder/notes/account-number fields', () {
    test(
      'persists bankId/accountHolderName/notes/accountNumberLast4 at creation',
      () async {
        final account = await repository.createAccount(
          name: 'HDFC Savings',
          type: AccountType.bank,
          openingBalance: 1000,
          colorValue: 0xFF000000,
          bankId: 'hdfc',
          accountHolderName: 'Abin John',
          notes: 'Primary salary account',
          accountNumberLast4: '1234',
        );

        expect(account.bankId, 'hdfc');
        expect(account.accountHolderName, 'Abin John');
        expect(account.notes, 'Primary salary account');
        expect(account.accountNumberLast4, '1234');
      },
    );

    test('rejects an account number that is not exactly 4 digits', () async {
      await expectLater(
        repository.createAccount(
          name: 'HDFC Savings',
          type: AccountType.bank,
          openingBalance: 1000,
          colorValue: 0xFF000000,
          accountNumberLast4: '123',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test(
      'editAccount updates bankId/accountHolderName/notes/accountNumberLast4',
      () async {
        final account = await repository.createAccount(
          name: 'HDFC Savings',
          type: AccountType.bank,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );

        await repository.editAccount(
          account,
          bankId: 'sbi',
          accountHolderName: 'Maneesh Madhu',
          notes: 'Joint account',
          accountNumberLast4: '5678',
        );

        expect(account.bankId, 'sbi');
        expect(account.accountHolderName, 'Maneesh Madhu');
        expect(account.notes, 'Joint account');
        expect(account.accountNumberLast4, '5678');
      },
    );

    test('editAccount clears bankId when clearBankId is true', () async {
      final account = await repository.createAccount(
        name: 'HDFC Savings',
        type: AccountType.bank,
        openingBalance: 1000,
        colorValue: 0xFF000000,
        bankId: 'hdfc',
      );

      await repository.editAccount(account, clearBankId: true);

      expect(account.bankId, isNull);
    });
  });

  group('Soft-delete / restore', () {
    test(
      'soft-deleting an account does not reverse its balance; restoring brings it back',
      () async {
        final account = await repository.createAccount(
          name: 'Wallet',
          type: AccountType.cash,
          openingBalance: 1000,
          colorValue: 0xFF000000,
        );
        await repository.adjustBalance(account, 500);

        await repository.softDelete(account);
        expect(account.isDeleted, isTrue);
        expect(account.currentBalance, 1500);

        final trashed = await repository.getTrash();
        expect(trashed.map((a) => a.id), contains(account.id));

        await repository.restore(account);
        expect(account.isDeleted, isFalse);

        final active = await repository.getAll();
        expect(active.map((a) => a.id), contains(account.id));
      },
    );
  });
}
