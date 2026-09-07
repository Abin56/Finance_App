import '../../../smart_import/domain/detected_transaction.dart';
import '../../../smart_import/presentation/providers/smart_import_state.dart'
    show ImportSummary;

enum PasteImportStage { pastingText, processing, reviewing, importing, done }

class PasteImportState {
  const PasteImportState({
    this.stage = PasteImportStage.pastingText,
    this.pastedText = '',
    this.detected = const [],
    this.accountId,
    this.errorMessage,
    this.importProgress,
    this.importResult,
  });

  final PasteImportStage stage;
  final String pastedText;
  final List<DetectedTransaction> detected;
  final String? accountId;

  /// Set on a recoverable failure (empty input, no transactions found) —
  /// always plain language, never technical parser detail.
  final String? errorMessage;

  /// (completed, total) while [stage] is [PasteImportStage.importing].
  final (int, int)? importProgress;

  final ImportSummary? importResult;

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

  PasteImportState copyWith({
    PasteImportStage? stage,
    String? pastedText,
    List<DetectedTransaction>? detected,
    String? accountId,
    bool clearAccountId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    (int, int)? importProgress,
    bool clearImportProgress = false,
    ImportSummary? importResult,
  }) {
    return PasteImportState(
      stage: stage ?? this.stage,
      pastedText: pastedText ?? this.pastedText,
      detected: detected ?? this.detected,
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      importProgress: clearImportProgress
          ? null
          : (importProgress ?? this.importProgress),
      importResult: importResult ?? this.importResult,
    );
  }
}
