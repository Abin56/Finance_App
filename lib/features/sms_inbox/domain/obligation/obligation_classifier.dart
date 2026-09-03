import '../financial_event/financial_event_type.dart';
import '../financial_event/reminder_signals.dart';
import '../financial_event/transaction_status.dart';
import 'obligation_semantic_bucket.dart';
import 'obligation_type.dart';

/// [ObligationClassifier]'s verdict on one financial-shaped SMS/event —
/// always carries a human-readable [reason], same transparency principle
/// every other detector/matcher in this feature follows (see
/// `ReminderVerdict`, `TransactionMatchOutcome`).
class ObligationClassificationResult {
  const ObligationClassificationResult({
    required this.bucket,
    required this.obligationType,
    required this.confidence,
    required this.reason,
  });

  final ObligationSemanticBucket bucket;

  /// Only meaningful when [bucket].isOutstanding — see
  /// [ObligationSemanticBucketX.isOutstanding].
  final ObligationType obligationType;

  /// 0.0-1.0.
  final double confidence;

  final String reason;

  /// The single most safety-critical question this whole engine exists to
  /// answer correctly: is it ever safe to treat this as a completed,
  /// real-money-movement transaction? See Safety rules 1-5.
  bool get isSafeToTreatAsCompletedTransaction =>
      bucket == ObligationSemanticBucket.completed;
}

/// Deterministic classification of a financial-shaped SMS/event into one of
/// [ObligationSemanticBucket]'s eight outcomes, plus (when outstanding) an
/// [ObligationType] subtype.
///
/// Deliberately layered *on top of* the existing pipeline's own
/// `TransactionStatus`/`FinancialEvent.moneyMovement`/`ReminderSignals`
/// rather than re-deriving "did money move" from scratch — this class never
/// re-implements tense/futurity detection (that already lives in
/// `ReminderSignals`, owned by the Phase 2/3 session); it only adds the
/// finer-grained reminder/upcoming/due split and the obligation-subtype
/// guess those callers don't need.
///
/// Callers that already have a reconciled `FinancialEvent` should pass its
/// `transactionStatus.value` and `moneyMovement.value` straight through —
/// this classifier only falls back to raw-text heuristics when those are
/// unavailable (e.g. evaluating a corpus case standalone).
class ObligationClassifier {
  const ObligationClassifier();

  ObligationClassificationResult classify({
    required String body,
    TransactionStatus? transactionStatus,
    bool? moneyMovement,
    FinancialEventType? eventType,
  }) {
    // Money confirmed to have moved: resolve via TransactionStatus, the
    // existing hard-fact field — never re-derived from text once we already
    // know money moved. TransactionStatus.unknown with moneyMovement==true
    // is treated as completed (the pipeline only ever sets moneyMovement
    // true on a success/unknown-status read, never on failed/pending).
    if (moneyMovement == true) {
      final bucket = transactionStatus == null
          ? ObligationSemanticBucket.completed
          : (ObligationSemanticBucketX.fromTransactionStatus(
                  transactionStatus,
                ) ??
                ObligationSemanticBucket.completed);
      return ObligationClassificationResult(
        bucket: bucket,
        obligationType: ObligationType.unknownObligation,
        confidence: 0.9,
        reason: 'Money movement was confirmed (${bucket.label.toLowerCase()}).',
      );
    }

    // Money confirmed NOT to have moved, but with a concrete settled
    // status (failed/pending/reversed/refunded) — these are resolutions in
    // their own right, not outstanding obligations to remind about.
    if (transactionStatus != null) {
      final settled = ObligationSemanticBucketX.fromTransactionStatus(
        transactionStatus,
      );
      if (settled != null && settled != ObligationSemanticBucket.completed) {
        return ObligationClassificationResult(
          bucket: settled,
          obligationType: ObligationType.unknownObligation,
          confidence: 0.85,
          reason:
              'Transaction status is ${transactionStatus.label.toLowerCase()} — not an outstanding obligation.',
        );
      }
    }

    // No confirmed money movement either way: fall back to text-based
    // reminder detection, reusing the existing ReminderSignals check as the
    // gate (never re-implemented here).
    final looksLikeReminder =
        eventType == FinancialEventType.reminder ||
        ReminderSignals.looksLikeReminder(body);
    if (!looksLikeReminder) {
      return const ObligationClassificationResult(
        bucket: ObligationSemanticBucket.unknown,
        obligationType: ObligationType.unknownObligation,
        confidence: 0.0,
        reason:
            'No completed-transaction or reminder signal found in this message.',
      );
    }

    final bucket = _refineOutstandingBucket(body);
    final obligationType = _classifyType(body, bucket);
    return ObligationClassificationResult(
      bucket: bucket,
      obligationType: obligationType,
      confidence: 0.75,
      reason:
          'This message reads as a ${bucket.label.toLowerCase()} — an outstanding obligation, not a completed transaction.',
    );
  }

  static final _dueDatePatterns = [
    RegExp(r'\bdue date\b', caseSensitive: false),
    RegExp(r'\bdue (on|tomorrow|today|this)\b', caseSensitive: false),
    RegExp(r'\bpayment due\b', caseSensitive: false),
    RegExp(r'\bwill be due\b', caseSensitive: false),
    RegExp(r'\bis due\b', caseSensitive: false),
    // Broad catch-all: only ever consulted on text ReminderSignals has
    // already gated as reminder-shaped, so a bare "due" anywhere (e.g.
    // "due next Monday", "due in 5 days") is a safe, specific-enough signal
    // to prefer the `due` bucket over the more generic `reminder` bucket.
    RegExp(r'\bdue\b', caseSensitive: false),
  ];

  static final _scheduledPatterns = [
    RegExp(
      r'\bwill be (debited|deducted|charged|auto[\s-]?debited)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bis scheduled to be\b', caseSensitive: false),
    RegExp(r'\bscheduled for\b', caseSensitive: false),
    RegExp(r'\bstanding instruction\b', caseSensitive: false),
    RegExp(r'\bshall be (debited|deducted|charged)\b', caseSensitive: false),
  ];

  /// Distinguishes [ObligationSemanticBucket.due] /
  /// [ObligationSemanticBucket.upcoming] / [ObligationSemanticBucket.reminder]
  /// once [ReminderSignals] has already confirmed the message is one of the
  /// three — an explicit due-date phrase wins over a scheduled-debit phrase,
  /// which wins over the generic reminder bucket, matching the specificity
  /// order a human reviewer would apply.
  ObligationSemanticBucket _refineOutstandingBucket(String body) {
    if (_dueDatePatterns.any((p) => p.hasMatch(body))) {
      return ObligationSemanticBucket.due;
    }
    if (_scheduledPatterns.any((p) => p.hasMatch(body))) {
      return ObligationSemanticBucket.upcoming;
    }
    return ObligationSemanticBucket.reminder;
  }

  ObligationType _classifyType(String body, ObligationSemanticBucket bucket) {
    final lower = body.toLowerCase();
    if (RegExp(r'\bemi\b').hasMatch(lower)) return ObligationType.emiObligation;
    if (RegExp(r'\bloan\b').hasMatch(lower))
      return ObligationType.loanObligation;
    if (RegExp(r'\bcredit card\b').hasMatch(lower)) {
      return ObligationType.creditCardDue;
    }
    if (RegExp(
      r'\b(subscription|renew(al)?|netflix|prime|spotify|hotstar|youtube premium)\b',
    ).hasMatch(lower)) {
      return ObligationType.subscriptionRenewal;
    }
    if (RegExp(r'\bbill\b').hasMatch(lower)) return ObligationType.billDue;

    switch (bucket) {
      case ObligationSemanticBucket.due:
        return ObligationType.duePayment;
      case ObligationSemanticBucket.upcoming:
        return ObligationType.upcomingDebit;
      case ObligationSemanticBucket.reminder:
        return ObligationType.paymentReminder;
      default:
        return ObligationType.unknownObligation;
    }
  }
}
