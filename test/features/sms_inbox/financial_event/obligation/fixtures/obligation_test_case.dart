import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_semantic_bucket.dart';
import 'package:finance_app/features/sms_inbox/domain/obligation/obligation_type.dart';

/// Ground truth for one [ObligationTestCase], graded by
/// `ObligationEvaluationHarness`. Every field is nullable/optional — a case
/// only asserts what it explicitly cares about, mirroring
/// `ExpectedFinancialClassification`'s convention in the sibling
/// `financial_event` corpus.
class ExpectedObligationClassification {
  const ExpectedObligationClassification({
    this.bucket,
    this.obligationType,
    this.isOutstanding,
    this.dueDateIsKnown,
    this.dueDateEquals,
    this.dueDateKind,
  });

  /// The single most safety-critical field: which of the eight semantic
  /// buckets this message resolves to. Getting this wrong in the
  /// `completed` direction on a reminder-shaped message is exactly the
  /// danger this whole engine exists to prevent.
  final ObligationSemanticBucket? bucket;

  final ObligationType? obligationType;

  /// Whether [bucket] is expected to be one that produces a
  /// [FinancialObligation] at all (reminder/upcoming/due).
  final bool? isOutstanding;

  /// Set `true`/`false` to assert whether a due/scheduled date could be
  /// resolved from the message text.
  final bool? dueDateIsKnown;

  /// Exact expected resolved date (compared on the calendar day only).
  final DateTime? dueDateEquals;

  final ObligationDateKindExpectation? dueDateKind;
}

/// Mirrors `ObligationDateKind` without importing it directly, so a test
/// case file can express "don't care" (`null`) without pulling in the enum
/// import at every call site — kept identical in shape for simplicity.
enum ObligationDateKindExpectation {
  dueDate,
  scheduledDebitDate,
  reminderDate,
  expiryDate,
  statementDate,
  paymentDeadline,
  unknown,
}

/// One entry in the Phase 4 obligation evaluation corpus: a raw SMS body
/// plus what the obligation engine is expected to conclude about it, and
/// why. Mirrors `SmsTestCase`'s structure (see
/// `test/features/sms_inbox/financial_event/fixtures/sms_test_case.dart`)
/// so both corpora can be read/maintained the same way.
class ObligationTestCase {
  const ObligationTestCase({
    required this.id,
    required this.body,
    required this.expected,
    required this.explanation,
    this.receivedAt,
    this.transactionStatus,
    this.moneyMovement,
    this.eventType,
    this.isDangerousIfMisclassified = false,
    this.knownIssue,
  });

  /// Stable id, e.g. `'emi-future-tense-01'`.
  final String id;

  final String body;

  /// When the SMS was received — the anchor for relative-date resolution.
  /// Defaults to a fixed date (see the harness) when omitted, so cases
  /// stay reproducible without every one of them specifying it.
  final DateTime? receivedAt;

  /// Optional hard-fact inputs a case can supply to simulate what the
  /// `FinancialEventExtractor` pipeline would have already reconciled —
  /// omitted when the case wants to exercise the classifier's own
  /// text-only fallback path.
  final TransactionStatus? transactionStatus;
  final bool? moneyMovement;
  final FinancialEventType? eventType;

  final ExpectedObligationClassification expected;

  final String explanation;

  /// Marks a case where a wrong [ExpectedObligationClassification.bucket]
  /// or [ExpectedObligationClassification.isOutstanding] verdict is not
  /// just a failed test but a financially dangerous misclassification —
  /// e.g. treating a future-tense EMI reminder as a completed transaction.
  /// The evaluation harness surfaces these separately and more loudly than
  /// an ordinary field mismatch, mirroring `SmsTestCase`'s convention.
  final bool isDangerousIfMisclassified;

  /// Set when this case is a confirmed, reproduced gap deliberately left
  /// unfixed in this foundation phase — graded but never counted as a
  /// failure. Mirrors `SmsTestCase.knownIssue`.
  final String? knownIssue;
}
