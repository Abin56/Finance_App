import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/smart_import/domain/screenshot_duplicate_detector.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `SmartImportController.import()`'s selection rule: only rows that
/// are selected, not already imported, and not an unacknowledged duplicate
/// are actually written. Kept identical in spirit to the controller so this
/// test exercises the same contract without pulling in Riverpod/image_picker
/// plumbing that has nothing to do with import correctness.
List<DetectedTransaction> _selectForImport(List<DetectedTransaction> detected) {
  final candidates = detected
      .where((d) => d.isSelected && !d.isImported)
      .toList();
  return candidates
      .where((d) => !d.isDuplicate || d.duplicateAcknowledged)
      .toList();
}

DetectedTransaction _row({
  required DateTime date,
  required String description,
  required double amount,
  String? categoryId = 'cat-1',
}) {
  return DetectedTransaction(
    id: description,
    sourceImageIndex: 0,
    rawText: '',
    date: date,
    rawDescription: description,
    amount: amount,
    type: TransactionType.expense,
    categoryId: categoryId,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late AccountRepository accountRepository;
  late TransactionRepository transactionRepository;
  late Account account;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    final accountsCollection = firestore
        .collection('accounts')
        .withConverter<Account>(
          fromFirestore: Account.fromFirestore,
          toFirestore: (a, _) => a.toFirestore(),
        );
    accountRepository = AccountRepository(accountsCollection);

    final transactionsCollection = firestore
        .collection('transactions')
        .withConverter<Transaction>(
          fromFirestore: Transaction.fromFirestore,
          toFirestore: (t, _) => t.toFirestore(),
        );
    transactionRepository = TransactionRepository(
      transactionsCollection,
      accountRepository,
    );

    account = await accountRepository.createAccount(
      name: 'Wallet',
      type: AccountType.cash,
      openingBalance: 1000,
      colorValue: 0xFF5B5FEF,
    );
  });

  Future<int> importSelected(List<DetectedTransaction> toImport) async {
    var imported = 0;
    for (final row in toImport) {
      await transactionRepository.createTransaction(
        type: row.type ?? TransactionType.expense,
        amount: row.amount!,
        dateTime: row.date!,
        accountId: account.id,
        categoryId: row.categoryId!,
        description: row.description,
        source: 'screenshot',
      );
      row.isImported = true;
      row.isSelected = false;
      imported++;
    }
    return imported;
  }

  group('Smart Import — import flow', () {
    test(
      'a successful import creates a real transaction through the shared repository',
      () async {
        final detected = [
          _row(date: DateTime(2026, 9, 5), description: 'Swiggy', amount: 420),
        ];

        final toImport = _selectForImport(detected);
        final imported = await importSelected(toImport);

        expect(imported, 1);
        final saved = await transactionRepository.getAll();
        expect(saved, hasLength(1));
        expect(saved.single.source, 'screenshot');
        expect(saved.single.amount, 420);
      },
    );

    test('a detected duplicate is skipped rather than imported', () async {
      await transactionRepository.createTransaction(
        type: TransactionType.expense,
        amount: 420,
        dateTime: DateTime(2026, 9, 5),
        accountId: account.id,
        categoryId: 'cat-1',
        description: 'Swiggy',
      );

      final detected = [
        _row(date: DateTime(2026, 9, 5), description: 'Swiggy', amount: 420),
        _row(date: DateTime(2026, 9, 6), description: 'Uber', amount: 185.50),
      ];
      ScreenshotDuplicateDetector.apply(
        detected,
        await transactionRepository.getAll(),
        accountId: account.id,
      );

      final toImport = _selectForImport(detected);
      expect(toImport, hasLength(1));
      expect(toImport.single.description, 'Uber');

      final imported = await importSelected(toImport);
      expect(imported, 1);

      final saved = await transactionRepository.getAll();
      expect(saved, hasLength(2)); // the pre-existing one + Uber
    });

    test(
      'a row referencing a since-deleted account fails without blocking the rest of the batch '
      '(and documents a pre-existing repository quirk: the transaction document is written '
      'before the account lookup, so the failed row still leaves an orphaned document behind — '
      "this is why SmartImportController checks the account exists before calling import() at "
      'all, rather than relying on this per-row try/catch)',
      () async {
        final detected = [
          _row(date: DateTime(2026, 9, 5), description: 'Swiggy', amount: 420),
          _row(date: DateTime(2026, 9, 6), description: 'Uber', amount: 185.50),
        ];

        var imported = 0;
        var failed = 0;
        for (final row in detected) {
          try {
            await transactionRepository.createTransaction(
              type: row.type ?? TransactionType.expense,
              amount: row.amount!,
              dateTime: row.date!,
              // The second row references an account that doesn't exist,
              // simulating a real partial-failure cause (a deleted account).
              accountId: row.description == 'Uber'
                  ? 'missing-account'
                  : account.id,
              categoryId: row.categoryId!,
              description: row.description,
              source: 'screenshot',
            );
            row.isImported = true;
            imported++;
          } catch (_) {
            failed++;
          }
        }

        expect(imported, 1);
        expect(failed, 1);
        // Both documents exist — `createTransaction` writes the transaction
        // before it looks up the account, so the failed row's document was
        // still created, just without its balance effect ever applied.
        final saved = await transactionRepository.getAll();
        expect(saved, hasLength(2));
        expect(
          saved.map((t) => t.description),
          containsAll(['Swiggy', 'Uber']),
        );
      },
    );

    test(
      'retrying after a successful import never creates the transaction twice',
      () async {
        final detected = [
          _row(date: DateTime(2026, 9, 5), description: 'Swiggy', amount: 420),
        ];

        await importSelected(_selectForImport(detected));
        expect(await transactionRepository.getAll(), hasLength(1));

        // A retry re-selects from the same list — the already-imported row
        // must be excluded by `isImported`, exactly like re-opening the
        // review screen and pressing Import again would do.
        final retrySelection = _selectForImport(detected);
        expect(retrySelection, isEmpty);

        final importedAgain = await importSelected(retrySelection);
        expect(importedAgain, 0);
        expect(await transactionRepository.getAll(), hasLength(1));
      },
    );
  });
}
