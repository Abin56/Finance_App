import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../smart_import/domain/detected_transaction.dart';
import '../../../smart_import/domain/screenshot_duplicate_detector.dart';
import '../../../smart_import/presentation/providers/smart_import_state.dart'
    show ImportSummary;
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/paste_transaction_extractor.dart';
import 'paste_import_state.dart';

final pasteImportControllerProvider =
    NotifierProvider<PasteImportController, PasteImportState>(
      PasteImportController.new,
    );

/// Owns one Copy/Paste Import session end-to-end: pasted text → extraction →
/// review edits → duplicate re-check → import. A sibling of
/// `SmartImportController` (the Screenshot import session owner) — same
/// stages, same duplicate-detection and import pipeline, same
/// `TransactionRepository` write path, but driven by plain pasted text
/// instead of OCR. Every write still goes through
/// [transactionRepositoryProvider] — this controller never touches Firestore
/// directly.
class PasteImportController extends Notifier<PasteImportState> {
  @override
  PasteImportState build() => const PasteImportState();

  void preselectAccount(String? accountId) {
    if (accountId == null || state.accountId != null) return;
    state = state.copyWith(accountId: accountId);
  }

  void setAccount(String accountId) {
    state = state.copyWith(accountId: accountId);
    _recheckDuplicates();
  }

  void setText(String text) {
    state = state.copyWith(pastedText: text, clearErrorMessage: true);
  }

  void clearText() {
    state = state.copyWith(pastedText: '', clearErrorMessage: true);
  }

  /// Only ever runs when the user explicitly asks — never automatically on
  /// screen open, matching platform clipboard-privacy expectations.
  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final combined = state.pastedText.isEmpty
        ? text
        : '${state.pastedText}\n$text';
    state = state.copyWith(pastedText: combined, clearErrorMessage: true);
  }

  void reset() => state = const PasteImportState();

  /// Parses [PasteImportState.pastedText] into candidates. Runs only when the
  /// user taps Analyze — never on every keystroke — so an arbitrarily long
  /// paste never causes per-character parsing work.
  void analyze() {
    final text = state.pastedText.trim();
    if (text.isEmpty) {
      state = state.copyWith(
        errorMessage:
            'No transaction text found.\n\nPaste transaction information and try again.',
      );
      return;
    }

    state = state.copyWith(
      stage: PasteImportStage.processing,
      clearErrorMessage: true,
    );

    final detected = PasteTransactionExtractor.extract(text);

    if (detected.isEmpty) {
      state = state.copyWith(
        stage: PasteImportStage.pastingText,
        errorMessage:
            "We couldn't detect any transactions.\n\n"
            'Try copying the transaction list including the date, description and amount.',
      );
      return;
    }

    _applyCategorySuggestions(detected);
    ScreenshotDuplicateDetector.apply(
      detected,
      ref.read(transactionsStreamProvider).value ?? const [],
      accountId: state.accountId,
    );

    state = state.copyWith(
      stage: PasteImportStage.reviewing,
      detected: detected,
    );
  }

  void _applyCategorySuggestions(List<DetectedTransaction> detected) {
    final categories = ref.read(categoriesStreamProvider).value ?? const [];
    final suggester = ref.read(merchantCategorySuggesterProvider);
    for (final row in detected) {
      final type = row.type ?? TransactionType.expense;
      final suggestion = suggester.suggest(
        merchant: row.rawDescription,
        transactionType: type,
        categories: categories,
      );
      if (suggestion != null) {
        row.categoryId = suggestion.categoryId;
        row.categorySuggestionSource = suggestion.source;
      }
    }
  }

  void _recheckDuplicates() {
    final updated = [...state.detected];
    ScreenshotDuplicateDetector.apply(
      updated,
      ref.read(transactionsStreamProvider).value ?? const [],
      accountId: state.accountId,
    );
    state = state.copyWith(detected: updated);
  }

  void toggleSelected(String id, bool selected) {
    _mutate(id, (row) => row.isSelected = selected);
  }

  void selectAll() {
    final updated = [...state.detected];
    for (final row in updated) {
      row.isSelected = true;
    }
    state = state.copyWith(detected: updated);
  }

  void deselectAll() {
    final updated = [...state.detected];
    for (final row in updated) {
      row.isSelected = false;
    }
    state = state.copyWith(detected: updated);
  }

  void skipDuplicate(String id) {
    _mutate(id, (row) {
      row.duplicateAcknowledged = false;
      row.isSelected = false;
    });
  }

  void importDuplicateAnyway(String id) {
    _mutate(id, (row) {
      row.duplicateAcknowledged = true;
      row.isSelected = true;
    });
  }

  void updateTransaction(
    String id, {
    DateTime? date,
    String? description,
    double? amount,
    TransactionType? type,
    String? categoryId,
  }) {
    _mutate(id, (row) {
      if (date != null) row.date = date;
      if (description != null) row.rawDescription = description;
      if (amount != null) row.amount = amount;
      if (type != null) row.type = type;
      if (categoryId != null) row.categoryId = categoryId;
    });
    _recheckDuplicates();
  }

  void removeTransaction(String id) {
    state = state.copyWith(
      detected: state.detected.where((d) => d.id != id).toList(),
    );
  }

  void _mutate(String id, void Function(DetectedTransaction row) apply) {
    final updated = [...state.detected];
    final row = updated.firstWhere((d) => d.id == id);
    apply(row);
    state = state.copyWith(detected: updated);
  }

  /// Imports every selected, non-duplicate, valid row through the same
  /// [TransactionRepository.createTransaction] path manual entry, SMS import
  /// and Screenshot import all use. Writes run sequentially (never
  /// `Future.wait`) so a failure partway through never leaves an inconsistent
  /// burst of balance adjustments. Already-imported rows are skipped
  /// unconditionally, so calling this again after a partial failure can never
  /// create a duplicate for anything that already succeeded.
  Future<void> import() async {
    final accountId = state.accountId;
    if (accountId == null) return;

    final accountStillExists =
        (ref.read(accountsStreamProvider).value ?? const []).any(
          (a) => a.id == accountId,
        );
    if (!accountStillExists) {
      state = state.copyWith(
        stage: PasteImportStage.reviewing,
        errorMessage:
            'That account no longer exists. Please choose another one.',
      );
      return;
    }

    final freshDetected = [...state.detected];
    ScreenshotDuplicateDetector.apply(
      freshDetected,
      ref.read(transactionsStreamProvider).value ?? const [],
      accountId: accountId,
    );
    state = state.copyWith(detected: freshDetected);

    final candidates = freshDetected
        .where((d) => d.isSelected && !d.isImported)
        .toList();
    final toImport = candidates
        .where((d) => !d.isDuplicate || d.duplicateAcknowledged)
        .toList();
    final skippedDuplicates = candidates.length - toImport.length;

    state = state.copyWith(
      stage: PasteImportStage.importing,
      importProgress: (0, toImport.length),
    );

    final repository = ref.read(transactionRepositoryProvider);
    var imported = 0;
    var failed = 0;

    for (var i = 0; i < toImport.length; i++) {
      final row = toImport[i];
      state = state.copyWith(importProgress: (i, toImport.length));

      if (!row.hasRequiredFields || row.categoryId == null) {
        failed++;
        continue;
      }

      try {
        await repository.createTransaction(
          type: row.type ?? TransactionType.expense,
          amount: row.amount!,
          dateTime: row.date!,
          accountId: accountId,
          categoryId: row.categoryId!,
          description: row.description,
          source: 'paste',
        );
        row.isImported = true;
        row.isSelected = false;
        imported++;

        await ref
            .read(merchantMemoriesProvider.notifier)
            .record(
              merchant: row.rawDescription,
              transactionType: row.type ?? TransactionType.expense,
              categoryId: row.categoryId!,
            );
      } catch (_) {
        failed++;
      }
    }

    state = state.copyWith(
      stage: PasteImportStage.done,
      clearImportProgress: true,
      detected: [...state.detected],
      importResult: ImportSummary(
        imported: imported,
        skippedDuplicates: skippedDuplicates,
        failed: failed,
      ),
    );
  }

  Future<void> retryImport() => import();
}
