import 'dart:io';

import '../../domain/detected_transaction.dart';

enum SmartImportStage { pickingImages, processing, reviewing, importing, done }

/// Outcome of one `SmartImportController.import()` run — shown on the
/// summary screen exactly as the numbers came out, never rounded up to a
/// blanket "Done" (mirrors how `SmsInboxScreen` reports bulk-action results).
class ImportSummary {
  const ImportSummary({
    required this.imported,
    required this.skippedDuplicates,
    required this.failed,
  });

  final int imported;
  final int skippedDuplicates;
  final int failed;

  bool get hasIssues => skippedDuplicates > 0 || failed > 0;
}

class SmartImportState {
  const SmartImportState({
    this.stage = SmartImportStage.pickingImages,
    this.images = const [],
    this.detected = const [],
    this.accountId,
    this.processingLabel,
    this.errorMessage,
    this.errorSequence = 0,
    this.importProgress,
    this.importResult,
  });

  final SmartImportStage stage;
  final List<File> images;
  final List<DetectedTransaction> detected;
  final String? accountId;

  /// User-friendly progress text ("Reading screenshot 2 of 3…") — never
  /// technical OCR/parser terminology.
  final String? processingLabel;

  /// Set on a recoverable failure (no text found, no transactions found, OCR
  /// crashed) — always plain language, never a stack trace.
  final String? errorMessage;

  /// Bumped by [copyWith] every time a new [errorMessage] is set, including
  /// when it's the same text as before (e.g. the user retries against the
  /// same still-invalid account twice in a row). A listener comparing
  /// [errorMessage] by string equality alone would silently swallow the
  /// second, identical failure's snackbar — comparing this instead makes
  /// every failure visible, not just ones with new wording.
  final int errorSequence;

  /// (completed, total) while [stage] is [SmartImportStage.importing].
  final (int, int)? importProgress;

  final ImportSummary? importResult;

  /// Rows that will actually be attempted if the user imports right now —
  /// selected, not an unacknowledged duplicate, and carrying every required
  /// field. Kept in one place so the review screen's button count/label and
  /// `SmartImportController.import()`'s own selection never drift apart.
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

  SmartImportState copyWith({
    SmartImportStage? stage,
    List<File>? images,
    List<DetectedTransaction>? detected,
    String? accountId,
    bool clearAccountId = false,
    String? processingLabel,
    bool clearProcessingLabel = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    (int, int)? importProgress,
    bool clearImportProgress = false,
    ImportSummary? importResult,
  }) {
    return SmartImportState(
      stage: stage ?? this.stage,
      images: images ?? this.images,
      detected: detected ?? this.detected,
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      processingLabel: clearProcessingLabel
          ? null
          : (processingLabel ?? this.processingLabel),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      errorSequence: errorMessage != null ? errorSequence + 1 : errorSequence,
      importProgress: clearImportProgress
          ? null
          : (importProgress ?? this.importProgress),
      importResult: importResult ?? this.importResult,
    );
  }
}
