import 'account_match_result.dart';
import 'parsed_sms_transaction.dart';
import 'sms_transaction_category.dart';

/// How confident [SmsConfidenceScorer] is that a [TransactionCandidate]
/// (`transaction_candidate.dart`) is ready to convert without correction.
/// Never exposes a false sense of precision beyond these three bands — see
/// [SmsConfidenceResult.score] for the underlying number, which exists for
/// sorting/debugging, not for display as if it meant something more precise
/// than "high/medium/low".
enum ConfidenceLevel { high, medium, low }

/// The scorer's verdict on one [ParsedSmsTransaction], plus why — every
/// [reasons] entry is written to be shown verbatim on a "Needs Review" card,
/// the same transparency principle `SmsDuplicateReason.explanation` already
/// follows for duplicate flags.
class SmsConfidenceResult {
  const SmsConfidenceResult({
    required this.level,
    required this.score,
    required this.needsReview,
    required this.reasons,
  });

  final ConfidenceLevel level;

  /// 0.0-1.0, the weighted signal combination [level] was bucketed from.
  final double score;

  /// True whenever a human should look at this candidate before it becomes
  /// a real transaction — always true for [ConfidenceLevel.medium]/[.low],
  /// and can also be true for [ConfidenceLevel.high] (e.g. a high-confidence
  /// parse that's still flagged as a possible duplicate).
  final bool needsReview;

  final List<String> reasons;
}

/// Combines the signals already produced elsewhere in the SMS pipeline — the
/// parser's own [ParsedSmsTransaction.confidence], [AccountCardMatcher]'s
/// match quality, and whether the event type/duplicate state are known —
/// into one reviewable verdict. Deliberately rule-based and deterministic,
/// no ML/AI: every input here already exists and is explainable on its own,
/// so combining them stays explainable too.
class SmsConfidenceScorer {
  const SmsConfidenceScorer();

  static const double _highThreshold = 0.75;
  static const double _mediumThreshold = 0.5;

  /// Weights sum to 1.0 across the three positive signals; [isDuplicate] is
  /// a flat penalty on top rather than a fourth weighted signal, since a
  /// duplicate doesn't make the *parse* any less trustworthy — it just means
  /// this specific message must not be auto-imported.
  static const double _parserWeight = 0.4;
  static const double _accountWeight = 0.35;
  static const double _categoryWeight = 0.25;
  static const double _duplicatePenalty = 0.25;

  SmsConfidenceResult score({
    required ParsedSmsTransaction parsed,
    required AccountMatchResult accountMatch,
    bool isDuplicate = false,
  }) {
    final reasons = <String>[];

    final parserScore = parsed.confidence.clamp(0.0, 1.0) * _parserWeight;
    if (parsed.confidence < 0.6) {
      reasons.add(
        'Parsed by a generic, lower-confidence parser rather than a bank-specific one.',
      );
    }

    double accountScore;
    if (accountMatch.isResolved && accountMatch.bankConfirmed) {
      accountScore = _accountWeight;
    } else if (accountMatch.isResolved) {
      accountScore = _accountWeight * 0.7;
    } else {
      accountScore = 0.0;
      reasons.add(accountMatch.matchReason);
    }

    double categoryScore;
    if (parsed.category == SmsTransactionCategory.unknown) {
      categoryScore = 0.0;
      reasons.add(
        'Could not confidently determine what kind of transaction this is.',
      );
    } else {
      categoryScore = _categoryWeight;
    }

    var total = parserScore + accountScore + categoryScore;
    if (isDuplicate) {
      total = (total - _duplicatePenalty).clamp(0.0, 1.0);
      reasons.add('Flagged as a possible duplicate of another message.');
    }
    total = total.clamp(0.0, 1.0);

    // An unresolved account caps the verdict at Low regardless of how well
    // everything else scored — "high confidence, unknown account" isn't a
    // state a candidate should ever surface (see the class-level examples
    // this scorer is written to match).
    final level = accountMatch.isResolved
        ? _levelFor(total)
        : ConfidenceLevel.low;
    final needsReview =
        level != ConfidenceLevel.high ||
        isDuplicate ||
        !accountMatch.isResolved;

    return SmsConfidenceResult(
      level: level,
      score: total,
      needsReview: needsReview,
      reasons: reasons,
    );
  }

  ConfidenceLevel _levelFor(double score) {
    if (score >= _highThreshold) return ConfidenceLevel.high;
    if (score >= _mediumThreshold) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }
}
