import 'learned_field.dart';

/// Summarizes what one `FinancialEventLearningService` call actually did,
/// so a caller (future UI) can show the user what changed without having to
/// re-derive it from `MerchantLearningProfile` diffs itself.
class LearningUpdateResult {
  const LearningUpdateResult({
    required this.merchantKey,
    required this.confirmedFields,
    required this.correctedFields,
    required this.confirmationsRecorded,
    required this.correctionsRecorded,
    required this.explanation,
  });

  /// A no-op result for an action that named no fields at all.
  factory LearningUpdateResult.empty(String merchantKey) => LearningUpdateResult(
    merchantKey: merchantKey,
    confirmedFields: const [],
    correctedFields: const [],
    confirmationsRecorded: 0,
    correctionsRecorded: 0,
    explanation: 'No fields were confirmed or corrected for "$merchantKey".',
  );

  final String merchantKey;

  /// Fields whose existing value was reaffirmed (no `CorrectionEvent`
  /// created). Includes fields the caller asked to correct that turned out
  /// to already match the current value.
  final List<LearnedFieldType> confirmedFields;

  /// Fields whose value actually changed, each producing exactly one
  /// `CorrectionEvent`.
  final List<LearnedFieldType> correctedFields;

  final int confirmationsRecorded;
  final int correctionsRecorded;
  final String explanation;

  bool get isNoOp => confirmedFields.isEmpty && correctedFields.isEmpty;
}
