import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/pdf_file_picker_service.dart';
import '../../data/services/pdf_statement_service.dart';
import '../../domain/pdf_open_outcome.dart';
import 'pdf_import_state.dart';

final pdfFilePickerServiceProvider = Provider<PdfFilePickerService>(
  (ref) => const PdfFilePickerService(),
);

final pdfStatementServiceProvider = Provider<PdfStatementService>(
  (ref) => SyncfusionPdfStatementService(),
);

final pdfImportControllerProvider =
    NotifierProvider<PdfImportController, PdfImportState>(
      PdfImportController.new,
    );

/// Phase 1: owns PDF selection through text extraction, including the
/// password-protected retry loop. Parsing the extracted text into
/// transactions and everything downstream (review, duplicate check, import)
/// is added in later phases, following the exact same
/// `TransactionRepository.createTransaction`-only write path
/// `SmartImportController`/`PasteImportController` already use.
class PdfImportController extends Notifier<PdfImportState> {
  @override
  PdfImportState build() => const PdfImportState();

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
    _handleOpenOutcome(outcome);
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
    _handleOpenOutcome(outcome, passwordAttempted: true);
  }

  void _handleOpenOutcome(
    PdfOpenOutcome outcome, {
    bool passwordAttempted = false,
  }) {
    switch (outcome.status) {
      case PdfOpenStatus.success:
        state = state.copyWith(
          stage: PdfImportStage.extracted,
          result: outcome.result,
          isPasswordProtected: state.isPasswordProtected || passwordAttempted,
        );
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
        state = state.copyWith(
          stage: PdfImportStage.pickingFile,
          errorMessage: "We couldn't find any transactions in this statement.",
        );
    }
  }

  void reset() => state = const PdfImportState();
}
