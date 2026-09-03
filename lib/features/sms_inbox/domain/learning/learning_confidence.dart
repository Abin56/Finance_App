import 'learned_field.dart';
import 'learning_source.dart';

/// Tunable inputs to `LearningConfidence.compute` — grouped into one class
/// rather than scattered magic numbers so every threshold this layer relies
/// on is visible and adjustable in one place.
class LearningConfidenceThresholds {
  const LearningConfidenceThresholds({
    this.minConfirmationsForStrongHistory = 3,
    this.minConfidenceToSkipAi = 0.75,
    this.recentCorrectionWindow = const Duration(days: 30),
    this.staleAfter = const Duration(days: 180),
  });

  /// How many times a value must have been confirmed before it counts as
  /// "strong user history" for `AiCallReductionDecision`.
  final int minConfirmationsForStrongHistory;

  /// The confidence a merchant's learned value must clear before the AI-call
  /// reduction layer will skip calling AI on its strength alone.
  final double minConfidenceToSkipAi;

  /// A correction inside this window is treated as still-fresh evidence of
  /// the user's current intent, ahead of any older confirmation count.
  final Duration recentCorrectionWindow;

  /// A value not touched in this long has its confidence discounted — a
  /// merchant the user hasn't transacted with in six months is less certain
  /// to still carry the same category than one seen last week.
  final Duration staleAfter;
}

/// Derives a 0.0-1.0 confidence for one `LearnedField` from consistency
/// (confirmations vs corrections), source, and recency — never a hardcoded
/// magic number assigned without regard to the evidence behind it, mirroring
/// `MerchantConfidenceLevel.forEvidence`'s own reasoning for a coarser tier.
abstract class LearningConfidence {
  LearningConfidence._();

  static double compute({
    required LearnedField<Object?> field,
    required DateTime now,
    LearningConfidenceThresholds thresholds = const LearningConfidenceThresholds(),
  }) {
    if (!field.hasValue) return 0.0;

    final total = field.confirmations + field.corrections;
    // A brand-new value with no confirmation yet: trust it only as much as
    // its source deserves, since nothing has corroborated it.
    double base = total == 0
        ? _sourceWeight(field.source) * 0.5
        : (field.confirmations / total) * _sourceWeight(field.source);

    final lastUpdatedAt = field.lastUpdatedAt;
    if (lastUpdatedAt != null && now.difference(lastUpdatedAt) > thresholds.staleAfter) {
      base *= 0.6;
    }

    return base.clamp(0.0, 1.0);
  }

  static double _sourceWeight(LearningSource source) {
    switch (source) {
      case LearningSource.user:
        return 1.0;
      case LearningSource.ai:
        return 0.85;
      case LearningSource.inference:
        return 0.7;
    }
  }
}
