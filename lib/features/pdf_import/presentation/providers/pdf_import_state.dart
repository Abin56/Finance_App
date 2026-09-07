import 'dart:io';

import '../../domain/pdf_extraction_result.dart';

/// Phase 1 only covers getting from "user picked a file" to "we have
/// extracted text in hand" — [extracting] through [extracted]. Later phases
/// add parsing/review/import stages the same way `SmartImportStage` does.
enum PdfImportStage {
  pickingFile,
  opening,
  awaitingPassword,
  extracting,
  extracted,
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
  /// (invalid PDF, empty PDF, unexpected failure) — never a stack trace.
  final String? errorMessage;

  /// Bumped whenever [errorMessage] is set, mirroring
  /// `SmartImportState.errorSequence` — lets a listener show every failure
  /// even if the message text repeats.
  final int errorSequence;

  PdfImportState copyWith({
    PdfImportStage? stage,
    File? file,
    PdfExtractionResult? result,
    bool? isPasswordProtected,
    String? passwordError,
    bool clearPasswordError = false,
    String? errorMessage,
    bool clearErrorMessage = false,
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
    );
  }
}
