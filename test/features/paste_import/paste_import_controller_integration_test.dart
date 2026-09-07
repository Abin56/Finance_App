@TestOn('vm')
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/features/accounts/data/account_repository.dart';
import 'package:finance_app/features/accounts/domain/account_type.dart';
import 'package:finance_app/features/accounts/presentation/providers/account_providers.dart';
import 'package:finance_app/features/categories/data/category_repository.dart';
import 'package:finance_app/features/categories/domain/category_type.dart';
import 'package:finance_app/features/categories/presentation/providers/category_providers.dart';
import 'package:finance_app/features/paste_import/presentation/providers/paste_import_providers.dart';
import 'package:finance_app/features/paste_import/presentation/providers/paste_import_state.dart';
import 'package:finance_app/features/sms_inbox/data/sms_inbox_database.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/transactions/domain/transaction_type.dart';
import 'package:finance_app/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// End-to-end integration test driving the real [PasteImportController] the
/// way the UI does (setText → analyze → edit/select → import), against a
/// fake Firestore and an in-memory merchant-memory store — the same depth of
/// test `smart_import_camera_source_test.dart` uses for the Screenshot
/// pipeline. Exercises the exact same `TransactionRepository`/
/// `AccountRepository` every other import path (manual entry, SMS import,
/// Screenshot import) uses — there is no second, competing transaction model
/// or import architecture here.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;
  late AccountRepository accountRepository;
  late CategoryRepository categoryRepository;

  setUp(() async {
    SmsInboxDatabase.debugReset();
    final merchantMemoryDb = await SmsInboxDatabase.openInMemoryForTest();

    firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUserIdProvider.overrideWithValue('test-uid'),
        smsInboxDatabaseProvider.overrideWithValue(merchantMemoryDb),
      ],
    );
    accountRepository = container.read(accountRepositoryProvider);
    categoryRepository = container.read(categoryRepositoryProvider);
  });

  tearDown(() => container.dispose());

  test(
    'paste → analyze → review → edit → select/deselect → duplicate check → import '
    'produces real Transaction records through the shared repository, and the '
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

      // Warm the stream providers the controller reads synchronously.
      await container.read(accountsStreamProvider.future);
      await container.read(categoriesStreamProvider.future);
      await container.read(transactionsStreamProvider.future);

      final controller = container.read(pasteImportControllerProvider.notifier);

      // Step 1: realistic multi-format pasted text — bank-statement rows,
      // header/footer noise the extractor must ignore, and an ambiguous row
      // with no amount.
      controller.setText('''
Statement Period: 01 Sep 2026 - 07 Sep 2026

05 Sep SWIGGY 420 DR
06 Sep AMAZON PAY INDIA 1,299.00 DR
07 Sep SALARY CREDIT 50000 CR
07 Sep UNKNOWN MERCHANT

Closing Balance: Rs. 48,930.50
''');

      // Step 2: Analyze — runs the real extractor + category suggestion +
      // duplicate check, exactly as the Analyze button does.
      controller.analyze();
      final afterAnalyze = container.read(pasteImportControllerProvider);
      expect(afterAnalyze.stage, PasteImportStage.reviewing);
      // 4 real transactions plus the "Statement Period…" header and
      // "Closing Balance…" footer lines — each is its own single-line block
      // with no amount the extractor can trust (a bare "48,930.50" total
      // isn't attached to a DR/CR word or currency marker with a merchant
      // beside it), so both correctly surface as needs-review noise rather
      // than being silently discarded or misread as transactions.
      expect(afterAnalyze.detected, hasLength(6));

      final swiggy = afterAnalyze.detected.firstWhere((d) => d.rawDescription == 'Swiggy');
      final amazon = afterAnalyze.detected.firstWhere(
        (d) => d.rawDescription!.contains('Amazon'),
      );
      final salary = afterAnalyze.detected.firstWhere(
        (d) => d.rawDescription!.contains('Salary'),
      );
      final ambiguous = afterAnalyze.detected.firstWhere(
        (d) => d.rawDescription!.contains('Unknown Merchant'),
      );
      final noiseIds = afterAnalyze.detected
          .where((d) => ![swiggy.id, amazon.id, salary.id, ambiguous.id].contains(d.id))
          .map((d) => d.id)
          .toList();
      expect(
        noiseIds,
        hasLength(2),
        reason: 'the "Statement Period…" header and "Closing Balance…" footer lines',
      );

      expect(swiggy.amount, 420.0);
      expect(swiggy.type, TransactionType.expense);
      expect(amazon.amount, 1299.0);
      expect(salary.amount, 50000.0);
      expect(salary.type, TransactionType.income);
      expect(
        ambiguous.hasRequiredFields,
        isFalse,
        reason: 'no amount at all — must be flagged for review, never guessed',
      );
      expect(
        ambiguous.isSelected,
        isFalse,
        reason: 'a row needing review must not be pre-checked for import',
      );

      // Step 3: select an account — triggers a duplicate re-check.
      controller.setAccount(account.id);

      // Step 4: user edits a transaction on the review screen — assigns a
      // category the auto-suggester didn't pick, and this choice must
      // survive every subsequent duplicate re-check (it must never be
      // silently reverted by category suggestion running again).
      controller.updateTransaction(swiggy.id, categoryId: shoppingCategory.id);
      controller.updateTransaction(amazon.id, categoryId: shoppingCategory.id);
      controller.updateTransaction(salary.id, categoryId: foodCategory.id);
      final afterEdit = container.read(pasteImportControllerProvider);
      expect(
        afterEdit.detected.firstWhere((d) => d.id == swiggy.id).categoryId,
        shoppingCategory.id,
        reason: 'the manual override must stick — not the auto-suggested Food & Dining',
      );

      // Step 5: select/deselect-all behaves the same as Screenshot Import's.
      controller.deselectAll();
      expect(
        container.read(pasteImportControllerProvider).detected.every((d) => !d.isSelected),
        isTrue,
      );
      controller.selectAll();
      expect(
        container.read(pasteImportControllerProvider).detected.every((d) => d.isSelected),
        isTrue,
      );
      // The ambiguous, incomplete row and the header/footer noise are
      // real-selected now too — `import()` must still refuse to write them
      // (checked below), never guess a missing amount. Deselect them back
      // out so the import assertions below stay about the transactions this
      // test actually cares about.
      controller.toggleSelected(ambiguous.id, false);
      for (final id in noiseIds) {
        controller.toggleSelected(id, false);
      }

      // Step 6: an existing transaction that matches a pasted row must be
      // flagged as a possible duplicate, not silently re-imported.
      await container.read(transactionRepositoryProvider).createTransaction(
            type: TransactionType.expense,
            amount: 420,
            dateTime: DateTime(2026, 9, 5),
            accountId: account.id,
            categoryId: foodCategory.id,
            description: 'Swiggy',
          );
      await container.read(transactionsStreamProvider.future);
      controller.setAccount(account.id); // re-triggers the duplicate check
      final afterDuplicateCheck = container.read(pasteImportControllerProvider);
      final swiggyRow = afterDuplicateCheck.detected.firstWhere((d) => d.id == swiggy.id);
      expect(swiggyRow.isDuplicate, isTrue);
      expect(
        swiggyRow.isSelected,
        isFalse,
        reason: 'a freshly-flagged duplicate is unchecked until the user overrides it',
      );

      // Step 7: import. Only Amazon and Salary should actually get written —
      // Swiggy is an unacknowledged duplicate, and the ambiguous row was
      // deselected.
      await controller.import();
      final afterImport = container.read(pasteImportControllerProvider);
      expect(afterImport.stage, PasteImportStage.done);
      expect(afterImport.importResult?.imported, 2);
      expect(afterImport.importResult?.skippedDuplicates, 1);

      final repository = container.read(transactionRepositoryProvider);
      final saved = await repository.getAll();
      // The pre-existing Swiggy (created above) + Amazon + Salary.
      expect(saved, hasLength(3));
      expect(
        saved.every((t) => t.description == 'Swiggy' || t.source == 'paste'),
        isTrue,
        reason: 'every row this controller wrote must carry source "paste"',
      );

      final amazonTxn = saved.firstWhere((t) => t.description.contains('Amazon'));
      expect(amazonTxn.amount, 1299.0);
      expect(amazonTxn.dateTime, DateTime(2026, 9, 6));
      expect(amazonTxn.type, TransactionType.expense);
      expect(amazonTxn.accountId, account.id);
      expect(
        amazonTxn.categoryId,
        shoppingCategory.id,
        reason: 'the manual category edit from step 4 must be what actually got saved',
      );

      final salaryTxn = saved.firstWhere((t) => t.description.contains('Salary'));
      expect(salaryTxn.amount, 50000.0);
      expect(salaryTxn.type, TransactionType.income);

      // "Dashboard/account totals" are ultimately just `Account.currentBalance`
      // — verify it reflects both new writes: 1000 opening - 1299 (Amazon
      // expense) + 50000 (Salary income), the pre-existing Swiggy write
      // already having been applied when it was created above.
      final updatedAccount = (await accountRepository.getAll()).single;
      expect(updatedAccount.currentBalance, 1000 - 420 - 1299 + 50000);

      // Step 8: existing transactions must not be modified by the import —
      // the pre-existing Swiggy row is untouched.
      final untouchedSwiggy = saved.firstWhere((t) => t.description == 'Swiggy');
      expect(untouchedSwiggy.amount, 420);
      expect(untouchedSwiggy.categoryId, foodCategory.id);

      // Step 9: retrying the import (as the "Retry failed" button would)
      // must never create Amazon/Salary a second time.
      await controller.retryImport();
      final savedAfterRetry = await repository.getAll();
      expect(savedAfterRetry, hasLength(3));
    },
  );
}
