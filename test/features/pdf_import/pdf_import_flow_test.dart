import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_transaction_parser.dart';
import 'package:finance_app/features/smart_import/domain/detected_transaction.dart';
import 'package:finance_app/features/smart_import/domain/screenshot_duplicate_detector.dart';
import 'package:finance_app/features/transactions/data/transaction_repository.dart';
import 'package:finance_app/features/transactions/domain/transaction.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `PdfImportController.import()`'s selection rule — see the
/// equivalent Paste/Screenshot import tests for why this is exercised
/// directly rather than through Riverpod plumbing that has nothing to do
/// with import correctness.
List<DetectedTransaction> _selectForImport(List<DetectedTransaction> detected) {
  final candidates = detected
      .where((d) => d.isSelected && !d.isImported)
      .toList();
  return candidates
      .where((d) => !d.isDuplicate || d.duplicateAcknowledged)
      .toList();
}

PdfTextLine _line(String text, double top, {double left = 0}) {
  return PdfTextLine(
    text: text,
    boundingBox: PdfBoundingBox(
      left: left,
      top: top,
      right: left + 200,
      bottom: top + 12,
    ),
    source: PdfTextSource.embedded,
  );
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
        source: 'pdf',
      );
      row.isImported = true;
      row.isSelected = false;
      imported++;
    }
    return imported;
  }

  group('PDF Import — end-to-end from statement PDF to real transactions', () {
    test(
      'a multi-page statement is parsed and imported through the shared repository',
      () async {
        final extraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.embedded,
              lines: [_line('05/09/2026 SWIGGY 420.00', 100)],
            ),
            PdfPageResult(
              pageNumber: 2,
              source: PdfTextSource.embedded,
              lines: [_line('06/09/2026 UBER 185.50', 100)],
            ),
          ],
        );

        final detected = PdfTransactionParser.extract(
          extraction,
          referenceDate: reference,
        );
        expect(detected, hasLength(2));

        final toImport = _selectForImport(detected);
        final imported = await importSelected(toImport);

        expect(imported, 2);
        final saved = await transactionRepository.getAll();
        expect(saved, hasLength(2));
        expect(saved.every((t) => t.source == 'pdf'), isTrue);
        expect(saved.map((t) => t.amount), containsAll([420.0, 185.50]));
      },
    );

    test(
      'a debit row and a credit row are both parsed and imported with the '
      'correct transaction type',
      () async {
        final extraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.embedded,
              lines: [
                _line('05/09/2026 ATM WDL 2,000.00 DR', 100),
                _line('06/09/2026 SALARY CREDIT 50,000.00 CR', 130),
              ],
            ),
          ],
        );

        final detected = PdfTransactionParser.extract(
          extraction,
          referenceDate: reference,
        );
        expect(detected, hasLength(2));

        final debit = detected.firstWhere((d) => d.amount == 2000.0);
        final credit = detected.firstWhere((d) => d.amount == 50000.0);
        expect(debit.type, TransactionType.expense);
        expect(credit.type, TransactionType.income);

        final toImport = _selectForImport(detected);
        final imported = await importSelected(toImport);
        expect(imported, 2);

        final saved = await transactionRepository.getAll();
        expect(
          saved.firstWhere((t) => t.amount == 2000.0).type,
          TransactionType.expense,
        );
        expect(
          saved.firstWhere((t) => t.amount == 50000.0).type,
          TransactionType.income,
        );
      },
    );

    test(
      'an uncertain (needs-review) row is excluded from import until edited',
      () async {
        // The second dated block has no amount at all anywhere in its
        // rows — needs review, never guessed at.
        final extraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.embedded,
              lines: [
                _line('05/09/2026 SWIGGY 420.00', 100),
                _line('06/09/2026 UNKNOWN MERCHANT NO AMOUNT HERE', 130),
              ],
            ),
          ],
        );

        final detected = PdfTransactionParser.extract(
          extraction,
          referenceDate: reference,
        );
        final swiggy = detected.firstWhere((d) => d.amount == 420.0);
        expect(swiggy.reviewStatus, DetectionReviewStatus.ready);

        final needsReview = detected.where(
          (d) => d.reviewStatus == DetectionReviewStatus.needsReview,
        );
        expect(needsReview, isNotEmpty);
        expect(needsReview.every((d) => !d.isSelected), isTrue);

        final toImport = _selectForImport(detected);
        expect(toImport, hasLength(1));
        expect(toImport.single.amount, 420.0);
      },
    );

    test(
      'a PDF transaction matching an existing one is flagged as a possible '
      'duplicate and skipped rather than silently re-imported',
      () async {
        await transactionRepository.createTransaction(
          type: TransactionType.expense,
          amount: 420,
          dateTime: DateTime(2026, 9, 5),
          accountId: account.id,
          categoryId: 'cat-1',
          description: 'Swiggy',
        );

        final extraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.embedded,
              lines: [
                _line('05/09/2026 SWIGGY 420.00', 100),
                _line('06/09/2026 UBER 185.50', 130),
              ],
            ),
          ],
        );
        final detected = PdfTransactionParser.extract(
          extraction,
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
        expect(toImport.single.description, 'UBER');

        final imported = await importSelected(toImport);
        expect(imported, 1);

        final saved = await transactionRepository.getAll();
        expect(saved, hasLength(2)); // pre-existing Swiggy + Uber
      },
    );

    test(
      'retrying after a successful import never creates the transaction twice',
      () async {
        final extraction = PdfExtractionResult(
          pages: [
            PdfPageResult(
              pageNumber: 1,
              source: PdfTextSource.embedded,
              lines: [_line('05/09/2026 SWIGGY 420.00', 100)],
            ),
          ],
        );
        final detected = PdfTransactionParser.extract(
          extraction,
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
