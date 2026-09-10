import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../smart_import/domain/detected_transaction.dart';
import '../../../smart_import/domain/screenshot_duplicate_detector.dart';
import '../../../smart_import/presentation/providers/smart_import_providers.dart'
    show transactionOcrServiceProvider;
import '../../../smart_import/presentation/providers/smart_import_state.dart'
    show ImportSummary;
import '../../../sms_inbox/presentation/providers/sms_inbox_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../data/services/pdf_file_picker_service.dart';
import '../../data/services/pdf_ocr_fallback_service.dart';
import '../../data/services/pdf_statement_service.dart';
import '../../domain/pdf_extraction_result.dart';
import '../../domain/pdf_open_outcome.dart';
import '../../domain/pdf_transaction_parser.dart';
import 'pdf_import_state.dart';

final pdfFilePickerServiceProvider = Provider<PdfFilePickerService>(
  (ref) => const PdfFilePickerService(),
);

final pdfStatementServiceProvider = Provider<PdfStatementService>(
  (ref) => SyncfusionPdfStatementService(),
);

/// Reuses the same on-device ML Kit recognizer Screenshot Import already
/// owns (`transactionOcrServiceProvider`) rather than spinning up a second
/// native recognizer instance — both features run fully offline and never
/// need more than one at a time.
final pdfOcrFallbackServiceProvider = Provider<PdfOcrFallbackService>(
  (ref) => PdfrxOcrFallbackService(ref.read(transactionOcrServiceProvider)),
);

final pdfImportControllerProvider =
    NotifierProvider<PdfImportController, PdfImportState>(
      PdfImportController.new,
    );

/// Owns one PDF Statement import session end-to-end: file selection →
/// password handling → text extraction → layout reconstruction/parsing →
/// review edits → duplicate re-check → import. A sibling of
/// `SmartImportController`/`PasteImportController` — same stages from
/// `parsing` onward, same duplicate-detection and import pipeline, same
/// `TransactionRepository` write path. Every write still goes through
/// [transactionRepositoryProvider] — this controller never touches Firestore
/// directly, and never creates a separate PDF-specific transaction store.
class PdfImportController extends Notifier<PdfImportState> {
  @override
  PdfImportState build() => const PdfImportState();

  /// Bumped by [reset] so a long-running async operation from a previous
  /// session (most importantly OCR fallback, which can run for many seconds
  /// on a large scanned statement) can tell it's stale once it resolves and
  /// skip applying its result — otherwise a user who backs out or resets
  /// mid-scan would have their fresh, reset state silently clobbered the
  /// moment that abandoned OCR call finally completes. See [_tryOcrFallback].
  int _sessionToken = 0;

  /// Returns true if a file was picked (regardless of what happens opening
  /// it) so the caller can decide whether to navigate on; false if the user
  /// cancelled the picker.
  Future<bool> pickFile() async {
    final outcome = await ref.read(pdfFilePickerServiceProvider).pickPdf();
    if (outcome.status == PdfPickStatus.cancelled) return false;

    state = state.copyWith(file: outcome.file, stage: PdfImportStage.opening);
    await _open();
    return true;
  }

  Future<void> _open() async {
    final file = state.file;
    if (file == null) return;

    state = state.copyWith(
      stage: PdfImportStage.extracting,
      clearErrorMessage: true,
    );
    final outcome = await ref.read(pdfStatementServiceProvider).open(file);
    await _handleOpenOutcome(outcome);
  }

  /// Called from the password dialog. Never retried automatically and never
  /// logged — see `PdfStatementService`.
  Future<void> submitPassword(String password) async {
    final file = state.file;
    if (file == null) return;

    state = state.copyWith(
      stage: PdfImportStage.extracting,
      clearPasswordError: true,
    );
    final outcome = await ref
        .read(pdfStatementServiceProvider)
        .openWithPassword(file, password);
    await _handleOpenOutcome(outcome, passwordAttempted: true);
  }

  Future<void> _handleOpenOutcome(
    PdfOpenOutcome outcome, {
    bool passwordAttempted = false,
  }) async {
    switch (outcome.status) {
      case PdfOpenStatus.success:
        state = state.copyWith(
          stage: PdfImportStage.extracted,
          result: outcome.result,
          isPasswordProtected: state.isPasswordProtected || passwordAttempted,
        );
        _parse();
      case PdfOpenStatus.passwordRequired:
        state = state.copyWith(
          stage: PdfImportStage.awaitingPassword,
          isPasswordProtected: true,
        );
      case PdfOpenStatus.incorrectPassword:
        state = state.copyWith(
          stage: PdfImportStage.awaitingPassword,
          isPasswordProtected: true,
          passwordError: 'Incorrect PDF password. Please try again.',
        );
      case PdfOpenStatus.invalidPdf:
        state = state.copyWith(
          stage: PdfImportStage.pickingFile,
          errorMessage: 'Unable to read this PDF.',
        );
      case PdfOpenStatus.empty:
        // No usable embedded text — try OCR before giving up, since this is
        // exactly as likely to be a scanned/photographed statement as a
        // genuinely empty one.
        await _tryOcrFallback();
    }
  }

  /// Rasterizes and OCRs every page via [PdfOcrFallbackService], reporting
  /// per-page progress through [PdfImportState.processingLabel] — the only
  /// place in this controller that runs meaningfully long enough to need
  /// progress text, since embedded-text extraction is effectively instant.
  /// Feeds its result into the exact same [_parse] path the embedded-text
  /// success case uses, so [PdfLayoutReconstructor]/[PdfTransactionParser]
  /// never need to know or care which path produced their input.
  Future<void> _tryOcrFallback() async {
    final file = state.file;
    if (file == null) return;

    final token = _sessionToken;
    state = state.copyWith(
      processingLabel: 'Checking for a scanned statement…',
    );

    final PdfExtractionResult ocrResult;
    try {
      ocrResult = await ref
          .read(pdfOcrFallbackServiceProvider)
          .extractViaOcr(
            file,
            onPageProgress: (current, total) {
              // Same staleness check as below — a page-progress update from
              // an abandoned scan must not resurrect its processingLabel
              // over whatever the (already-reset) current session is doing.
              if (token != _sessionToken) return;
              state = state.copyWith(
                processingLabel: total == 1
                    ? 'Scanning page…'
                    : 'Scanning page $current of $total…',
              );
            },
          );
    } catch (_) {
      if (token != _sessionToken) return;
      // Rasterization/OCR failure reads the same as "no transactions found"
      // to the user — never a stack trace, and never distinguished from the
      // plain-empty case, which would leak implementation detail without
      // giving the user anything actionable.
      state = state.copyWith(
        stage: PdfImportStage.pickingFile,
        clearProcessingLabel: true,
        errorMessage: "We couldn't find any transactions in this statement.",
      );
      return;
    }

    // The user backed out, reset, or started a new session while this scan
    // was still running — its result belongs to a session that no longer
    // exists, so it must never overwrite whatever the current one is doing.
    if (token != _sessionToken) return;

    if (!ocrResult.hasAnyText) {
      state = state.copyWith(
        stage: PdfImportStage.pickingFile,
        clearProcessingLabel: true,
        errorMessage: "We couldn't find any transactions in this statement.",
      );
      return;
    }

    state = state.copyWith(
      stage: PdfImportStage.extracted,
      result: ocrResult,
      clearProcessingLabel: true,
    );
    _parse();
  }

  /// Runs [PdfTransactionParser] over the just-extracted text. Split out
  /// from [_handleOpenOutcome] (rather than folded into the `success` case
  /// inline) so a future retry/re-parse action has somewhere to call back
  /// into without re-opening the file.
  void _parse() {
    final result = state.result;
    if (result == null) return;

    state = state.copyWith(stage: PdfImportStage.parsing);

    final List<DetectedTransaction> detected;
    try {
      detected = PdfTransactionParser.extract(result);
    } catch (_) {
      // A parser crash on some pathological statement layout must still
      // land the user back on a recoverable screen, never leave `parsing`
      // (treated as a busy/spinning stage by the UI) stuck forever.
      state = state.copyWith(
        stage: PdfImportStage.pickingFile,
        errorMessage: 'Unable to read this PDF.',
      );
      return;
    }

    if (detected.isEmpty) {
      state = state.copyWith(
        stage: PdfImportStage.pickingFile,
        errorMessage:
            "We couldn't find any transactions in this statement.\n\n"
            'The PDF opened successfully, but no transaction-shaped rows '
            'were detected.',
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
      stage: PdfImportStage.reviewing,
      detected: detected,
    );
  }

  void preselectAccount(String? accountId) {
    if (accountId == null || state.accountId != null) return;
    state = state.copyWith(accountId: accountId);
  }

  void setAccount(String accountId) {
    state = state.copyWith(accountId: accountId);
    _recheckDuplicates();
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
  /// [TransactionRepository.createTransaction] path manual entry, SMS
  /// import, Screenshot import and Paste import all use. Writes run
  /// sequentially (never `Future.wait`) so a failure partway through never
  /// leaves an inconsistent burst of balance adjustments. Already-imported
  /// rows are skipped unconditionally, so calling this again after a
  /// partial failure can never create a duplicate for anything that already
  /// succeeded.
  Future<void> import() async {
    if (state.stage == PdfImportStage.importing) return;

    final accountId = state.accountId;
    if (accountId == null) return;

    final accountStillExists =
        (ref.read(accountsStreamProvider).value ?? const []).any(
          (a) => a.id == accountId,
        );
    if (!accountStillExists) {
      state = state.copyWith(
        stage: PdfImportStage.reviewing,
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
      stage: PdfImportStage.importing,
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
          source: 'pdf',
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
      stage: PdfImportStage.done,
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

  void reset() {
    _sessionToken++;
    state = const PdfImportState();
  }
}
