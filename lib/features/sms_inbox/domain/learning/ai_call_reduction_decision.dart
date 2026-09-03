import 'learned_field.dart';
import 'learning_confidence.dart';
import 'learning_source.dart';
import 'merchant_preference_resolver.dart';

/// Why `AiCallReductionDecider.decide` landed where it did. Ordered here in
/// the same priority this class documents, most-trusted first — current SMS
/// hard evidence (amount/direction/account/status/reference) is not a member
/// of this enum at all, and never will be: this decision has no field for it
/// and no way to receive it, by design.
enum AiCallReductionReason {
  knownMerchant,
  userHistory,
  recentCorrection,
  strongPattern,
  unknownMerchant,
  conflictingEvidence,
  insufficientConfidence,
}

/// The outcome: whether to spend an AI call, why, how confident that call is,
/// and a human-readable explanation to show the user — same transparency
/// principle every other resolver in this feature already follows (compare
/// `MerchantIdentity.evidence`, `FinancialEvent.reviewReasons`).
class AiCallReductionDecision {
  const AiCallReductionDecision({
    required this.shouldCallAi,
    required this.reason,
    required this.confidence,
    required this.source,
    required this.explanation,
  });

  final bool shouldCallAi;
  final AiCallReductionReason reason;
  final double confidence;
  final LearningSource source;
  final String explanation;
}

/// Decides whether an AI call is worth making for a merchant's *category*
/// classification, given what's already been learned about it.
///
/// This is deliberately scoped to category/merchant-identity learning only —
/// it has no parameters for amount, direction, account, status, or reference
/// number, and cannot decide anything about them. Those fields are hard SMS
/// evidence reconciled by `FinancialEventExtractor`/`TransactionMatcher` and
/// must never be second-guessed by merchant memory; keeping them entirely
/// outside this API's surface is how that boundary is enforced, not a
/// runtime check on values that don't exist here.
///
/// Priority order (most trusted first): a recent explicit user correction >
/// strong, consistent user history > an already-known merchant (catalog or
/// prior AI/inference above the confidence bar) > insufficient confidence or
/// unresolved conflicts, both of which fall back to calling AI.
abstract class AiCallReductionDecider {
  AiCallReductionDecider._();

  static AiCallReductionDecision decide({
    required String? merchantKey,
    required LearnedField<String> categoryField,
    required List<MerchantFieldObservation<String>> categoryObservations,
    required DateTime now,
    bool hasStrongRecurringPattern = false,
    LearningConfidenceThresholds thresholds = const LearningConfidenceThresholds(),
  }) {
    if (merchantKey == null || merchantKey.trim().isEmpty) {
      return const AiCallReductionDecision(
        shouldCallAi: true,
        reason: AiCallReductionReason.unknownMerchant,
        confidence: 0.0,
        source: LearningSource.inference,
        explanation: 'No merchant identity resolved yet — nothing learned to reuse.',
      );
    }

    final recentCorrections =
        categoryObservations
            .where(
              (o) =>
                  o.isCorrection &&
                  now.difference(o.timestamp) <= thresholds.recentCorrectionWindow,
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (recentCorrections.isNotEmpty) {
      return AiCallReductionDecision(
        shouldCallAi: false,
        reason: AiCallReductionReason.recentCorrection,
        confidence: 0.95,
        source: LearningSource.user,
        explanation:
            'You recently corrected this merchant\'s category to "${recentCorrections.first.value}" — using that.',
      );
    }

    if (categoryObservations.isEmpty) {
      if (hasStrongRecurringPattern) {
        return AiCallReductionDecision(
          shouldCallAi: false,
          reason: AiCallReductionReason.strongPattern,
          confidence: thresholds.minConfidenceToSkipAi,
          source: LearningSource.inference,
          explanation: 'This matches a recurring transaction pattern for this merchant.',
        );
      }
      return const AiCallReductionDecision(
        shouldCallAi: true,
        reason: AiCallReductionReason.unknownMerchant,
        confidence: 0.0,
        source: LearningSource.inference,
        explanation: 'No prior history for this merchant yet.',
      );
    }

    final counts = <String, int>{};
    for (final observation in categoryObservations) {
      counts[observation.value] = (counts[observation.value] ?? 0) + 1;
    }
    if (counts.length > 1) {
      final sortedCounts = counts.values.toList()..sort((a, b) => b.compareTo(a));
      if (sortedCounts[0] - sortedCounts[1] <= 1) {
        return const AiCallReductionDecision(
          shouldCallAi: true,
          reason: AiCallReductionReason.conflictingEvidence,
          confidence: 0.4,
          source: LearningSource.inference,
          explanation:
              'This merchant has been filed under multiple categories before — not confident enough to skip AI.',
        );
      }
    }

    final resolution = MerchantPreferenceResolver.resolve(categoryObservations)!;
    final confidence = LearningConfidence.compute(
      field: categoryField,
      now: now,
      thresholds: thresholds,
    );

    if (confidence >= thresholds.minConfidenceToSkipAi) {
      final observationCount = categoryObservations
          .where((o) => o.value == resolution.value)
          .length;
      final isStrongHistory =
          categoryField.source == LearningSource.user &&
          categoryField.confirmations >= thresholds.minConfirmationsForStrongHistory;

      return AiCallReductionDecision(
        shouldCallAi: false,
        reason: isStrongHistory
            ? AiCallReductionReason.userHistory
            : AiCallReductionReason.knownMerchant,
        confidence: confidence,
        source: categoryField.source,
        explanation: isStrongHistory
            ? 'Based on your previous $observationCount transactions for this merchant.'
            : 'This merchant is already known.',
      );
    }

    return AiCallReductionDecision(
      shouldCallAi: true,
      reason: AiCallReductionReason.insufficientConfidence,
      confidence: confidence,
      source: categoryField.source,
      explanation: 'Not confident enough yet to skip AI for this merchant.',
    );
  }
}
