import '../sms_confidence_scorer.dart';
import 'financial_event.dart';

/// Configurable thresholds/weights for [FinancialEventConfidenceEngine] —
/// deliberately not hardcoded constants (unlike the old per-bank 0.85/0.7/0.5
/// literals this engine supersedes for `FinancialEvent`s), so a future
/// settings screen can expose "AI confidence threshold" without touching the
/// engine itself.
///
/// Weights only cover fields [FinancialEvent] actually carries a
/// [FieldConfidence] for (amount, account, merchant, category, payment
/// method) — there is no separate weighted slot for direction/eventType
/// disagreement, since those are hard-fact/derived fields the extractor
/// already folds into [FinancialEvent.needsReview]/`reviewReasons` directly
/// rather than a numeric field-confidence.
class FinancialEventConfidenceThresholds {
  const FinancialEventConfidenceThresholds({
    this.highThreshold = 0.75,
    this.mediumThreshold = 0.5,
    this.amountWeight = 0.30,
    this.accountWeight = 0.30,
    this.merchantWeight = 0.15,
    this.categoryWeight = 0.15,
    this.paymentMethodWeight = 0.10,
  });

  final double highThreshold;
  final double mediumThreshold;
  final double amountWeight;
  final double accountWeight;
  final double merchantWeight;
  final double categoryWeight;
  final double paymentMethodWeight;
}

/// Scores a [FinancialEvent] into an overall [ConfidenceLevel] — the
/// `FinancialEvent` analog of [SmsConfidenceScorer], which keeps scoring
/// plain `TransactionCandidate`s unchanged (this engine does not replace it,
/// only supersedes it for the new pipeline — see the SMS AI rebuild plan §7).
class FinancialEventConfidenceEngine {
  const FinancialEventConfidenceEngine({
    this.thresholds = const FinancialEventConfidenceThresholds(),
  });

  final FinancialEventConfidenceThresholds thresholds;

  ({double overall, ConfidenceLevel level, List<String> reasons}) score(
    FinancialEvent event,
  ) {
    final reasons = <String>[...event.reviewReasons];

    final amountScore =
        event.amount.confidence.clamp(0.0, 1.0) * thresholds.amountWeight;

    double accountScore;
    if (event.accountMatch.value != null) {
      accountScore =
          event.accountMatch.confidence.clamp(0.0, 1.0) *
          thresholds.accountWeight;
    } else {
      accountScore = 0.0;
    }

    final merchantScore =
        event.merchant.confidence.clamp(0.0, 1.0) * thresholds.merchantWeight;
    final categoryScore =
        event.category.confidence.clamp(0.0, 1.0) * thresholds.categoryWeight;
    final paymentMethodScore =
        event.paymentMethod.confidence.clamp(0.0, 1.0) *
        thresholds.paymentMethodWeight;

    final total =
        (amountScore +
                accountScore +
                merchantScore +
                categoryScore +
                paymentMethodScore)
            .clamp(0.0, 1.0);

    // Same hard invariant `SmsConfidenceScorer` already enforces: an
    // unresolved account always caps the verdict at Low, regardless of how
    // well every other field scored — a wrong or missing account
    // attribution quietly mis-files spending, and no amount of merchant/
    // category confidence should be allowed to paper over that.
    final level = event.accountMatch.value == null
        ? ConfidenceLevel.low
        : _levelFor(total);

    return (overall: total, level: level, reasons: reasons);
  }

  ConfidenceLevel _levelFor(double score) {
    if (score >= thresholds.highThreshold) return ConfidenceLevel.high;
    if (score >= thresholds.mediumThreshold) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }
}
