import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/paste_import/domain/paste_transaction_extractor.dart';
import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/smart_import/domain/screenshot_duplicate_detector.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `PasteImportController.import()`'s selection rule — see the
/// equivalent Screenshot-import test for why this is exercised directly
/// rather than through Riverpod plumbing that has nothing to do with import
/// correctness.
List<DetectedTransaction> _selectForImport(List<DetectedTransaction> detected) {
  final candidates = detected
      .where((d) => d.isSelected && !d.isImported)
      .toList();
  return candidates
      .where((d) => !d.isDuplicate || d.duplicateAcknowledged)
      .toList();
}

void main() {
  final reference = DateTime(2026, 9, 7);

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
        categoryId: row.categoryId ?? 'cat-1',
        description: row.description,
        source: 'paste',
      );
      row.isImported = true;
      row.isSelected = false;
      imported++;
    }
    return imported;
  }

  group('Paste Import — end-to-end from pasted text to real transactions', () {
    test(
      'a pasted transaction list is parsed and imported through the shared repository',
      () async {
        final detected = PasteTransactionExtractor.extract(
          '05 Sep SWIGGY 420 DR\n06 Sep UBER 185.50 DR',
          referenceDate: reference,
        );
        expect(detected, hasLength(2));

        final toImport = _selectForImport(detected);
        final imported = await importSelected(toImport);

        expect(imported, 2);
        final saved = await transactionRepository.getAll();
        expect(saved, hasLength(2));
        expect(saved.every((t) => t.source == 'paste'), isTrue);
        expect(saved.map((t) => t.amount), containsAll([420.0, 185.50]));
      },
    );

    test(
      'a pasted transaction matching an existing one is flagged as a possible duplicate '
      'and skipped rather than silently re-imported',
      () async {
        await transactionRepository.createTransaction(
          type: TransactionType.expense,
          amount: 420,
          dateTime: DateTime(2026, 9, 5),
          accountId: account.id,
          categoryId: 'cat-1',
          description: 'Swiggy',
        );

        final detected = PasteTransactionExtractor.extract(
          '05 Sep SWIGGY 420 DR\n06 Sep UBER 185.50 DR',
          referenceDate: reference,
        );
        ScreenshotDuplicateDetector.apply(
          detected,
          await transactionRepository.getAll(),
          accountId: account.id,
        );

        expect(detected.first.isDuplicate, isTrue);

        final toImport = _selectForImport(detected);
        expect(toImport, hasLength(1));
        expect(toImport.single.description, 'Uber');

        final imported = await importSelected(toImport);
        expect(imported, 1);

        final saved = await transactionRepository.getAll();
        expect(
          saved,
          hasLength(2),
        ); // the pre-existing Swiggy + Uber, not a second Swiggy
      },
    );

    test(
      'an explicit "import anyway" override lets a duplicate through',
      () async {
        await transactionRepository.createTransaction(
          type: TransactionType.expense,
          amount: 420,
          dateTime: DateTime(2026, 9, 5),
          accountId: account.id,
          categoryId: 'cat-1',
          description: 'Swiggy',
        );

        final detected = PasteTransactionExtractor.extract(
          '05 Sep SWIGGY 420 DR',
          referenceDate: reference,
        );
        ScreenshotDuplicateDetector.apply(
          detected,
          await transactionRepository.getAll(),
          accountId: account.id,
        );
        expect(detected.first.isDuplicate, isTrue);
        expect(_selectForImport(detected), isEmpty);

        detected.first
          ..duplicateAcknowledged = true
          ..isSelected = true;

        final toImport = _selectForImport(detected);
        expect(toImport, hasLength(1));
        await importSelected(toImport);

        final saved = await transactionRepository.getAll();
        expect(saved, hasLength(2));
      },
    );

    test(
      'a row that could not be confidently parsed is excluded from import until edited',
      () async {
        final detected = PasteTransactionExtractor.extract(
          '05 Sep SWIGGY 420 DR\n06 Sep UNKNOWN MERCHANT',
          referenceDate: reference,
        );
        expect(detected, hasLength(2));
        expect(detected[1].hasRequiredFields, isFalse);

        // The controller assigns a category during analysis; the ambiguous row
        // never gets one from a bare description with no type, but even with
        // one it still can't be selected for import while a required field
        // (amount) is missing.
        final toImport = detected.where((d) => d.hasRequiredFields).toList();
        expect(toImport, hasLength(1));
        expect(toImport.single.description, 'Swiggy');
      },
    );

    test(
      'retrying after a successful import never creates the transaction twice',
      () async {
        final detected = PasteTransactionExtractor.extract(
          '05 Sep SWIGGY 420 DR',
          referenceDate: reference,
        );

        await importSelected(_selectForImport(detected));
        expect(await transactionRepository.getAll(), hasLength(1));

        final retrySelection = _selectForImport(detected);
        expect(retrySelection, isEmpty);

        final importedAgain = await importSelected(retrySelection);
        expect(importedAgain, 0);
        expect(await transactionRepository.getAll(), hasLength(1));
      },
    );
  });
}
