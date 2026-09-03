import 'transaction_status.dart';

/// Deterministic, regex-based reading of a message's transaction-lifecycle
/// status — "did this money movement actually complete." Checked before
/// [ReminderSignals] gets the final say on `moneyMovement`, since a failed
/// or pending transaction is exactly as non-actionable as a reminder (no
/// real money moved) even though the wording is otherwise transaction-
/// shaped, not reminder-shaped.
abstract class TransactionStatusSignals {
  TransactionStatusSignals._();

  static final List<RegExp> _failedPatterns = [
    RegExp(r'\b(has\s+)?failed\b', caseSensitive: false),
    RegExp(r'\bdeclined\b', caseSensitive: false),
    RegExp(r'\bunsuccessful\b', caseSensitive: false),
    RegExp(r'\bcould not be (processed|completed)\b', caseSensitive: false),
    RegExp(r'\binsufficient (balance|funds)\b', caseSensitive: false),
    RegExp(r'\btransaction (was )?declined\b', caseSensitive: false),
    RegExp(r'\bnot (been )?successful\b', caseSensitive: false),
  ];

  static final List<RegExp> _pendingPatterns = [
    RegExp(r'\bpending\b', caseSensitive: false),
    RegExp(r'\bprocessing\b', caseSensitive: false),
    RegExp(r'\bawaiting confirmation\b', caseSensitive: false),
    RegExp(r'\bin progress\b', caseSensitive: false),
    RegExp(r'\bunder process\b', caseSensitive: false),
    RegExp(r'\byet to be confirmed\b', caseSensitive: false),
  ];

  static final List<RegExp> _reversedPatterns = [
    RegExp(r'\breversed\b', caseSensitive: false),
    RegExp(r'\breversal\b', caseSensitive: false),
  ];

  static final List<RegExp> _refundedPatterns = [
    RegExp(r'\brefunded\b', caseSensitive: false),
    RegExp(r'\brefund of\b', caseSensitive: false),
  ];

  static final List<RegExp> _successPatterns = [
    RegExp(r'\bsuccessful\b', caseSensitive: false),
    RegExp(r'\bsuccessfully\b', caseSensitive: false),
    RegExp(
      r'\bhas been (debited|credited|paid|received|processed)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bwas (debited|credited|paid|received)\b', caseSensitive: false),
  ];

  /// A bare completion verb with no explicit "successful"/"has been" framing
  /// around it — the standard, terse phrasing of the vast majority of real
  /// bank SMS ("Rs.500 debited from a/c XX1234..."). Distinct from
  /// [_successPatterns]: this is *inferred* evidence of success (the mere
  /// presence of a completed-action verb, in the standard convention bank
  /// SMS follows of only ever using these verbs for completed transactions),
  /// not an *explicit* status statement — see [detectDetailed]'s
  /// [StatusDetectionResult.isInferred].
  static final RegExp _bareCompletionVerbPattern = RegExp(
    r'\b(debited|credited|paid|received|deposited|withdrawn|sent|charged|transferred)\b',
    caseSensitive: false,
  );

  /// Ordered most-specific-first: a message is checked against failed →
  /// reversed → refunded → pending → explicit-success → inferred-success,
  /// so e.g. "refund of a failed transaction reversed" resolves to the more
  /// specific/actionable [TransactionStatus.reversed] rather than a generic
  /// failure. Returns [TransactionStatus.unknown] only when there is truly
  /// no evidence at all (the extractor treats that permissively, see its
  /// reconciliation rule) — see [detectDetailed] for the known/inferred
  /// distinction; this is the plain convenience wrapper most callers want.
  static TransactionStatus detect(String body) => detectDetailed(body).status;

  /// Same detection as [detect], but also reports whether the verdict came
  /// from explicit status wording ("successful", "has been debited") or was
  /// merely *inferred* from a bare completion verb ("Rs.500 debited...",
  /// with no "successful"/"has been" framing) — the "known vs. inferred"
  /// distinction the field-confidence model elsewhere in this feature
  /// already applies to merchant/category/amount.
  static StatusDetectionResult detectDetailed(String body) {
    if (_failedPatterns.any((p) => p.hasMatch(body))) {
      return const StatusDetectionResult(
        status: TransactionStatus.failed,
        isInferred: false,
      );
    }
    if (_reversedPatterns.any((p) => p.hasMatch(body))) {
      return const StatusDetectionResult(
        status: TransactionStatus.reversed,
        isInferred: false,
      );
    }
    if (_refundedPatterns.any((p) => p.hasMatch(body))) {
      return const StatusDetectionResult(
        status: TransactionStatus.refunded,
        isInferred: false,
      );
    }
    if (_pendingPatterns.any((p) => p.hasMatch(body))) {
      return const StatusDetectionResult(
        status: TransactionStatus.pending,
        isInferred: false,
      );
    }
    if (_successPatterns.any((p) => p.hasMatch(body))) {
      return const StatusDetectionResult(
        status: TransactionStatus.success,
        isInferred: false,
      );
    }
    if (_bareCompletionVerbPattern.hasMatch(body)) {
      return const StatusDetectionResult(
        status: TransactionStatus.success,
        isInferred: true,
      );
    }
    return const StatusDetectionResult(
      status: TransactionStatus.unknown,
      isInferred: false,
    );
  }
}

/// See [TransactionStatusSignals.detectDetailed].
class StatusDetectionResult {
  const StatusDetectionResult({required this.status, required this.isInferred});

  final TransactionStatus status;
  final bool isInferred;
}
