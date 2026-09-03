import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/event_relationship_type.dart';
import 'package:finance_app/features/sms_inbox/domain/linking/match_confidence.dart';

/// One entry in the Phase 5 linking evaluation corpus: a newly-processed
/// candidate [FinancialEvent], the [pool] of already-known events it's
/// evaluated against, and what [EventRelationshipEngine] is expected to
/// conclude. Mirrors `ObligationTestCase`/`SmsTestCase`'s structure so all
/// three corpora in this feature can be read/maintained the same way.
class LinkingTestCase {
  const LinkingTestCase({
    required this.id,
    required this.candidate,
    required this.pool,
    required this.expectedType,
    required this.explanation,
    this.expectedConfidence,
    this.expectedTargetEventId,
    this.expectedNeedsReview,
    this.expectedAlternativeCount,
    this.isDangerousIfMisclassified = false,
    this.knownIssue,
  });

  final String id;
  final FinancialEvent candidate;
  final List<FinancialEvent> pool;

  final EventRelationshipType expectedType;
  final MatchConfidence? expectedConfidence;

  /// Set only when a specific target is expected (omit for ambiguous
  /// [EventRelationshipType.possibleMatch] cases, where no single target
  /// should ever be asserted).
  final String? expectedTargetEventId;

  final bool? expectedNeedsReview;

  /// Set for [EventRelationshipType.possibleMatch] cases to assert exactly
  /// how many candidates tied.
  final int? expectedAlternativeCount;

  final String explanation;

  /// Marks a case where a wrong verdict is not just a failed test but a
  /// financially dangerous misclassification (see Part 18 of the task) —
  /// graded and surfaced separately/more loudly by the evaluation harness.
  final bool isDangerousIfMisclassified;

  /// Set when this case is a confirmed, reproduced gap deliberately left
  /// unfixed in this foundation phase — graded but never counted as a
  /// failure. Mirrors `SmsTestCase.knownIssue`/`ObligationTestCase.knownIssue`.
  final String? knownIssue;
}
