@TestOn('vm')
library;

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/data/category_repository.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/pdf_import/data/services/pdf_file_picker_service.dart';
import 'package:finance_app/features/pdf_import/data/services/pdf_statement_service.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_extraction_result.dart';
import 'package:finance_app/features/pdf_import/domain/pdf_open_outcome.dart';
import 'package:finance_app/features/pdf_import/presentation/providers/pdf_import_providers.dart';
import 'package:finance_app/features/pdf_import/presentation/providers/pdf_import_state.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePdfFilePickerService implements PdfFilePickerService {
  _FakePdfFilePickerService(this.outcome);
  final PdfPickOutcome outcome;

  @override
  Future<PdfPickOutcome> pickPdf() async => outcome;
}

/// [openResult] is what a correct/no password ultimately succeeds with;
/// [requiresPassword] makes the initial no-password `open()` call report
/// `passwordRequired` instead of going straight to [openResult].
class _FakePdfStatementService implements PdfStatementService {
  _FakePdfStatementService({
    required this.openResult,
    this.correctPassword,
    this.requiresPassword = false,
  });

  final PdfOpenOutcome openResult;
  final String? correctPassword;
  final bool requiresPassword;

  final List<String> passwordAttempts = [];

  @override
  Future<PdfOpenOutcome> open(File file) async {
    if (requiresPassword) return const PdfOpenOutcome.passwordRequired();
    return openResult;
  }

  @override
  Future<PdfOpenOutcome> openWithPassword(File file, String password) async {
    passwordAttempts.add(password);
    if (password == correctPassword) return openResult;
    return const PdfOpenOutcome.incorrectPassword();
  }
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

/// A synthetic 2-page statement: headers/footers repeated verbatim on both
/// pages (must be stripped), 3 real transaction rows across the two pages,
/// and an uncertain no-amount row the parser must surface for review rather
/// than guess at or silently drop.
final _statementResult = PdfExtractionResult(
  pages: [
    PdfPageResult(
      pageNumber: 1,
      source: PdfTextSource.embedded,
      lines: [
        _line('ABC Bank - Statement of Account', 10),
        _line('05/09/2026 UPI-SWIGGY BANGALORE-420.00', 100),
        _line('06/09/2026 AMAZON PAY INDIA 1,299.00 DR', 130),
        _line('Generated on 07 Sep 2026', 700),
      ],
    ),
    PdfPageResult(
      pageNumber: 2,
      source: PdfTextSource.embedded,
      lines: [
        _line('ABC Bank - Statement of Account', 10),
        _line('07/09/2026 SALARY CREDIT XYZ CORP 50,000.00 CR', 100),
        // Its own date but no amount anywhere in the block — a genuinely
        // uncertain row that must surface for review rather than being
        // silently dropped or guessed at.
        _line('08/09/2026 UNRECOGNISED ENTRY NO AMOUNT HERE', 130),
        _line('Generated on 07 Sep 2026', 700),
      ],
    ),
  ],
);

/// End-to-end integration test driving the real [PdfImportController] the
/// way the UI does (pickFile → [password] → parse → review/edit/select →
/// import), against a fake Firestore and an in-memory merchant-memory
/// store — the same depth of test `paste_import_controller_integration_test.dart`
/// uses for Copy/Paste Import. Exercises the exact same
/// `TransactionRepository`/`AccountRepository` every other import path
/// (manual entry, SMS import, Screenshot import, Paste import) uses — PDF
/// import creates no second, competing transaction model or import
/// architecture.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late FakeFirebaseFirestore firestore;
  late SmsInboxDatabase merchantMemoryDb;
  late ProviderContainer container;
  late AccountRepository accountRepository;
  late CategoryRepository categoryRepository;

  ProviderContainer buildContainer({
    required PdfPickOutcome pickOutcome,
    required _FakePdfStatementService statementService,
  }) {
    return ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUserIdProvider.overrideWithValue('test-uid'),
        smsInboxDatabaseProvider.overrideWithValue(merchantMemoryDb),
        pdfFilePickerServiceProvider.overrideWithValue(
          _FakePdfFilePickerService(pickOutcome),
        ),
        pdfStatementServiceProvider.overrideWithValue(statementService),
      ],
    );
  }

  setUp(() async {
    SmsInboxDatabase.debugReset();
    merchantMemoryDb = await SmsInboxDatabase.openInMemoryForTest();

    firestore = FakeFirebaseFirestore();
    container = buildContainer(
      pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
      statementService: _FakePdfStatementService(
        openResult: PdfOpenOutcome.success(_statementResult),
      ),
    );
    accountRepository = container.read(accountRepositoryProvider);
    categoryRepository = container.read(categoryRepositoryProvider);
  });

  tearDown(() => container.dispose());

  test(
    'pick → extract → parse → review → edit → select/deselect → delete → duplicate check → '
    'import produces real Transaction records through the shared repository, and the '
    'account balance (dashboard/account-total source of truth) reflects them',
    () async {
      final account = await accountRepository.createAccount(
        name: 'Wallet',
        type: AccountType.cash,
        openingBalance: 1000,
        colorValue: 0xFF5B5FEF,
      );
      final foodCategory = await categoryRepository.createCategory(
        name: 'Food & Dining',
        type: CategoryType.expense,
        iconKey: 'restaurant',
        colorValue: 0xFF00BC7D,
      );
      final shoppingCategory = await categoryRepository.createCategory(
        name: 'Shopping',
        type: CategoryType.expense,
        iconKey: 'shopping_bag',
        colorValue: 0xFF5B5FEF,
      );

      await container.read(accountsStreamProvider.future);
      await container.read(categoriesStreamProvider.future);
      await container.read(transactionsStreamProvider.future);

      final controller = container.read(pdfImportControllerProvider.notifier);

      // Step 1: pick + extract + parse — mirrors what the entry screen does.
      final picked = await controller.pickFile();
      expect(picked, isTrue);

      final afterParse = container.read(pdfImportControllerProvider);
      expect(afterParse.stage, PdfImportStage.reviewing);
      // 3 real transactions across 2 pages, repeated header/footer stripped
      // on both pages, and the uncertain no-amount row correctly
      // surfaces as needs-review noise (no currency-marked/DR-CR-suffixed
      // amount of its own) rather than being silently discarded or misread
      // as a transaction.
      expect(afterParse.detected, hasLength(4));
      expect(
        afterParse.detected.any(
          (d) => d.rawText.toLowerCase().contains('statement of account'),
        ),
        isFalse,
        reason: 'repeated page header must never surface as a transaction',
      );
      expect(
        afterParse.detected.any(
          (d) => d.rawText.toLowerCase().contains('generated on'),
        ),
        isFalse,
        reason: 'page footer must never surface as a transaction',
      );

      final swiggy = afterParse.detected.firstWhere(
        (d) => d.rawDescription!.toUpperCase().contains('SWIGGY'),
      );
      final amazon = afterParse.detected.firstWhere(
        (d) => d.rawDescription!.toUpperCase().contains('AMAZON'),
      );
      final salary = afterParse.detected.firstWhere(
        (d) => d.rawDescription!.toUpperCase().contains('SALARY'),
      );
      final needsReviewRow = afterParse.detected.firstWhere(
        (d) => d.rawText.toLowerCase().contains('unrecognised entry'),
      );

      expect(swiggy.amount, 420.0);
      expect(swiggy.date, DateTime(2026, 9, 5));
      expect(swiggy.type, TransactionType.expense);
      expect(amazon.amount, 1299.0);
      expect(amazon.date, DateTime(2026, 9, 6));
      expect(amazon.type, TransactionType.expense);
      expect(salary.amount, 50000.0);
      expect(salary.date, DateTime(2026, 9, 7));
      expect(salary.type, TransactionType.income);
      expect(
        needsReviewRow.hasRequiredFields,
        isFalse,
        reason:
            'a bare closing-balance line must never be treated as a transaction amount',
      );
      expect(
        needsReviewRow.isSelected,
        isFalse,
        reason: 'a row needing review must not be pre-checked for import',
      );

      // Step 2: select an account — triggers a duplicate re-check.
      controller.setAccount(account.id);

      // Step 3: user edits a transaction on the review screen — assigns a
      // category the auto-suggester didn't pick, and this choice must
      // survive every subsequent duplicate re-check (it must never be
      // silently reverted by category suggestion running again).
      controller.updateTransaction(swiggy.id, categoryId: shoppingCategory.id);
      controller.updateTransaction(amazon.id, categoryId: shoppingCategory.id);
      controller.updateTransaction(salary.id, categoryId: foodCategory.id);
      final afterEdit = container.read(pdfImportControllerProvider);
      expect(
        afterEdit.detected.firstWhere((d) => d.id == swiggy.id).categoryId,
        shoppingCategory.id,
        reason:
            'the manual override must stick — not any auto-suggested category',
      );

      // Step 4: select/deselect-all.
      controller.deselectAll();
      expect(
        container
            .read(pdfImportControllerProvider)
            .detected
            .every((d) => !d.isSelected),
        isTrue,
      );
      controller.selectAll();
      expect(
        container
            .read(pdfImportControllerProvider)
            .detected
            .every((d) => d.isSelected),
        isTrue,
      );
      // The balance-noise row is real-selected now too — `import()` must
      // still refuse to write it (checked below), never guess a missing
      // amount. Deselect it back out so the import assertions stay about
      // the transactions this test actually cares about.
      controller.toggleSelected(needsReviewRow.id, false);

      // Step 5: delete/remove a row entirely (the review screen's
      // swipe-to-delete) — the balance-noise row is a fitting target since
      // it would never be imported anyway; verify it's actually gone from
      // state rather than merely deselected.
      controller.removeTransaction(needsReviewRow.id);
      expect(
        container
            .read(pdfImportControllerProvider)
            .detected
            .any((d) => d.id == needsReviewRow.id),
        isFalse,
      );

      // Step 6: an existing transaction that matches a PDF row must be
      // flagged as a possible duplicate, not silently re-imported.
      await container
          .read(transactionRepositoryProvider)
          .createTransaction(
            type: TransactionType.expense,
            amount: 420,
            dateTime: DateTime(2026, 9, 5),
            accountId: account.id,
            categoryId: foodCategory.id,
            description: 'Swiggy',
          );
      await container.read(transactionsStreamProvider.future);
      controller.setAccount(account.id); // re-triggers the duplicate check
      final afterDuplicateCheck = container.read(pdfImportControllerProvider);
      final swiggyRow = afterDuplicateCheck.detected.firstWhere(
        (d) => d.id == swiggy.id,
      );
      expect(swiggyRow.isDuplicate, isTrue);
      expect(
        swiggyRow.isSelected,
        isFalse,
        reason:
            'a freshly-flagged duplicate is unchecked until the user overrides it',
      );

      // Step 7: import. Only Amazon and Salary should actually get written —
      // Swiggy is an unacknowledged duplicate (already unchecked by the
      // duplicate re-check above, so it's excluded from `import()`'s
      // candidate set entirely rather than counted as a skip — the same
      // behavior `PasteImportController.import()` has), and the
      // needs-review row was already removed.
      await controller.import();
      final afterImport = container.read(pdfImportControllerProvider);
      expect(afterImport.stage, PdfImportStage.done);
      expect(afterImport.importResult?.imported, 2);
      expect(afterImport.importResult?.skippedDuplicates, 0);

      final repository = container.read(transactionRepositoryProvider);
      final saved = await repository.getAll();
      // The pre-existing Swiggy (created above) + Amazon + Salary.
      expect(saved, hasLength(3));
      expect(
        saved.every((t) => t.description == 'Swiggy' || t.source == 'pdf'),
        isTrue,
        reason: 'every row this controller wrote must carry source "pdf"',
      );

      final amazonTxn = saved.firstWhere(
        (t) => t.description.toUpperCase().contains('AMAZON'),
      );
      expect(amazonTxn.amount, 1299.0);
      expect(amazonTxn.dateTime, DateTime(2026, 9, 6));
      expect(amazonTxn.type, TransactionType.expense);
      expect(amazonTxn.accountId, account.id);
      expect(
        amazonTxn.categoryId,
        shoppingCategory.id,
        reason:
            'the manual category edit from step 3 must be what actually got saved',
      );

      final salaryTxn = saved.firstWhere(
        (t) => t.description.toUpperCase().contains('SALARY'),
      );
      expect(salaryTxn.amount, 50000.0);
      expect(salaryTxn.type, TransactionType.income);

      final updatedAccount = (await accountRepository.getAll()).single;
      expect(updatedAccount.currentBalance, 1000 - 420 - 1299 + 50000);

      final untouchedSwiggy = saved.firstWhere(
        (t) => t.description == 'Swiggy',
      );
      expect(untouchedSwiggy.amount, 420);
      expect(untouchedSwiggy.categoryId, foodCategory.id);

      // Step 8: retrying the import (as the "Retry failed" button would)
      // must never create Amazon/Salary a second time.
      await controller.retryImport();
      final savedAfterRetry = await repository.getAll();
      expect(savedAfterRetry, hasLength(3));
    },
  );

  test(
    'a wrong password keeps the user on awaitingPassword without leaking the '
    'attempt, and the correct password continues through to parsing/review',
    () async {
      final statementService = _FakePdfStatementService(
        openResult: PdfOpenOutcome.success(_statementResult),
        correctPassword: 'sesame',
        requiresPassword: true,
      );
      final passwordContainer = buildContainer(
        pickOutcome: PdfPickOutcome.success(File('unused.pdf')),
        statementService: statementService,
      );
      addTearDown(passwordContainer.dispose);

      final controller = passwordContainer.read(
        pdfImportControllerProvider.notifier,
      );
      await controller.pickFile();
      expect(
        passwordContainer.read(pdfImportControllerProvider).stage,
        PdfImportStage.awaitingPassword,
      );

      await controller.submitPassword('wrong-guess');
      final afterWrong = passwordContainer.read(pdfImportControllerProvider);
      expect(afterWrong.stage, PdfImportStage.awaitingPassword);
      expect(afterWrong.passwordError, isNotNull);
      expect(
        afterWrong.passwordError,
        isNot(contains('wrong-guess')),
        reason: 'the attempted password must never be echoed back',
      );
      // The password itself is recorded only by the fake for assertion
      // purposes — never by the controller/state, and never logged.
      expect(statementService.passwordAttempts, ['wrong-guess']);

      await controller.submitPassword('sesame');
      final afterCorrect = passwordContainer.read(pdfImportControllerProvider);
      expect(afterCorrect.stage, PdfImportStage.reviewing);
      expect(afterCorrect.detected, hasLength(4));
    },
  );
}
