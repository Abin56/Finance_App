import 'dart:io';

import '../../../smart_import/domain/detected_transaction.dart';
import '../../../smart_import/presentation/providers/smart_import_state.dart'
    show ImportSummary;
import '../../domain/pdf_extraction_result.dart';

/// Phase 3 extends Phase 1's extraction-only stages with the same
/// parse → review → import shape `PasteImportStage`/`SmartImportStage`
/// already use, so PDF Import's session lifecycle reads identically to its
/// siblings once a statement's text is in hand.
enum PdfImportStage {
  pickingFile,
  opening,
  awaitingPassword,
  extracting,
  extracted,
  parsing,
  reviewing,
  importing,
  done,
}

class PdfImportState {
  const PdfImportState({
    this.stage = PdfImportStage.pickingFile,
    this.file,
    this.result,
    this.isPasswordProtected = false,
    this.passwordError,
    this.errorMessage,
    this.errorSequence = 0,
    this.detected = const [],
    this.accountId,
    this.importProgress,
    this.importResult,
    this.processingLabel,
  });

  final PdfImportStage stage;
  final File? file;

  /// Set once [stage] reaches [PdfImportStage.extracted].
  final PdfExtractionResult? result;

  /// True once the PDF has been confirmed encrypted — kept even after a
  /// correct password succeeds, purely so the UI can say "this statement is
  /// password protected" contextually later if useful; does not gate any
  /// behavior itself.
  final bool isPasswordProtected;

  /// Set after a wrong password attempt, shown inline on the password
  /// dialog so the user can retry without the whole screen flashing an
  /// error banner — cleared as soon as a new attempt is submitted.
  final String? passwordError;

  /// Plain-language failure shown for anything that isn't "wrong password"
  /// (invalid PDF, empty PDF, no transactions found, unexpected failure) —
  /// never a stack trace.
  final String? errorMessage;

  /// Bumped whenever [errorMessage] is set, mirroring
  /// `SmartImportState.errorSequence` — lets a listener show every failure
  /// even if the message text repeats.
  final int errorSequence;

  /// Set once [PdfTransactionParser] has produced candidates — mirrors
  /// `PasteImportState.detected`/`SmartImportState.detected` exactly, so the
  /// same review screen/tile/edit-sheet plumbing works unchanged.
  final List<DetectedTransaction> detected;

  final String? accountId;

  /// (completed, total) while [stage] is [PdfImportStage.importing].
  final (int, int)? importProgress;

  final ImportSummary? importResult;

  /// User-friendly progress text ("Scanning page 2 of 8…") shown while
  /// [stage] is [PdfImportStage.extracting] and OCR fallback is running —
  /// mirrors `SmartImportState.processingLabel`. Null (and unused) for the
  /// embedded-text path, since that's effectively instant.
  final String? processingLabel;

  int get readyCount => detected
      .where(
        (d) =>
            d.isSelected &&
            d.hasRequiredFields &&
            (!d.isDuplicate || d.duplicateAcknowledged),
      )
      .length;

  int get needsReviewCount => detected
      .where((d) => d.reviewStatus == DetectionReviewStatus.needsReview)
      .length;

  PdfImportState copyWith({
    PdfImportStage? stage,
    File? file,
    PdfExtractionResult? result,
    bool? isPasswordProtected,
    String? passwordError,
    bool clearPasswordError = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<DetectedTransaction>? detected,
    String? accountId,
    bool clearAccountId = false,
    (int, int)? importProgress,
    bool clearImportProgress = false,
    ImportSummary? importResult,
    String? processingLabel,
    bool clearProcessingLabel = false,
  }) {
    return PdfImportState(
      stage: stage ?? this.stage,
      file: file ?? this.file,
      result: result ?? this.result,
      isPasswordProtected: isPasswordProtected ?? this.isPasswordProtected,
      passwordError: clearPasswordError
          ? null
          : (passwordError ?? this.passwordError),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      errorSequence: errorMessage != null ? errorSequence + 1 : errorSequence,
      detected: detected ?? this.detected,
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      importProgress: clearImportProgress
          ? null
          : (importProgress ?? this.importProgress),
      importResult: importResult ?? this.importResult,
      processingLabel: clearProcessingLabel
          ? null
          : (processingLabel ?? this.processingLabel),
    );
  }
}
