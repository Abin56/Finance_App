import '../financial_event/field_confidence.dart';
import '../financial_event/payment_method.dart';
import 'obligation_date_resolver.dart';
import 'obligation_recurrence.dart';
import 'obligation_source.dart';
import 'obligation_status.dart';
import 'obligation_type.dart';

/// A Phase 4 domain record of a financial obligation/reminder — money that
/// is owed but has not (yet, as far as this engine has observed) moved.
///
/// Deliberately a sibling of `FinancialEvent`, not a subclass or a
/// duplicate of it: a `FinancialEvent` with `eventType == reminder` is the
/// raw, single-SMS read; a [FinancialObligation] is the longer-lived
/// tracked record built from one (see `ObligationBuilder`) and potentially
/// updated by several — the due date firming up, a payment attempt, an
/// eventual link to the [FinancialEvent] that actually resolves it.
///
/// Every value field uses [FieldConfidence] where the source pipeline
/// provides one, consistent with `FinancialEvent`'s own convention — this
/// class never invents a value neither the extractor nor a date match
/// could support (Safety rules 11-14).
class FinancialObligation {
  const FinancialObligation({
    required this.id,
    required this.sourceEventIds,
    required this.obligationType,
    required this.title,
    required this.merchant,
    required this.amount,
    required this.dueDate,
    required this.recurrence,
    required this.accountMatch,
    required this.paymentMethod,
    required this.status,
    required this.confidence,
    required this.evidence,
    required this.source,
    required this.reviewReasons,
    required this.createdAt,
    required this.updatedAt,
    this.currency = 'INR',
    this.expectedTransactionDate,
    this.reminderDate,
    this.referenceNumber,
    this.linkedEventId,
  });

  final String id;

  /// Every `FinancialEvent.id`/SMS id that contributed evidence to this
  /// obligation — a duplicate reminder for the same due date is folded in
  /// here rather than creating a second obligation (see
  /// `ObligationLinker`/dedup handling upstream).
  final List<String> sourceEventIds;

  final ObligationType obligationType;

  /// Short display name, e.g. "HDFC Credit Card — Due 5 Sep".
  final String title;

  final FieldConfidence<String> merchant;
  final FieldConfidence<double> amount;
  final String currency;

  /// The resolved due/scheduled date this obligation is tracked against —
  /// see [ObligationDateResolver]. `dueDate.value == null` is a valid,
  /// honest state: the amount/merchant may still be known even when no
  /// date could be resolved.
  final ResolvedObligationDate dueDate;

  /// Set only when [dueDate.kind] is
  /// [ObligationDateKind.scheduledDebitDate] — the date an auto-debit is
  /// expected to actually execute, distinct from a due date the user must
  /// act on themselves.
  final ResolvedObligationDate? expectedTransactionDate;

  /// Set only when a distinct reminder-only date was found alongside a
  /// different due/scheduled date in the same message (Part 3's "multiple
  /// dates in one SMS" case).
  final ResolvedObligationDate? reminderDate;

  final ObligationRecurrence recurrence;

  final FieldConfidence<String> accountMatch;
  final FieldConfidence<PaymentMethod> paymentMethod;

  final String? referenceNumber;

  final ObligationStatus status;

  /// 0.0-1.0, from [ObligationClassifier].
  final double confidence;

  /// Human-readable evidence strings shown verbatim to a reviewing user —
  /// same transparency principle `FinancialEvent.reviewReasons` follows.
  final List<String> evidence;

  final ObligationSource source;

  /// Set once a completed [FinancialEvent] is linked as resolving this
  /// obligation (see `ObligationLinker`) — never set by guessing, only by
  /// an explicit match.
  final String? linkedEventId;

  final List<String> reviewReasons;

  final DateTime createdAt;
  final DateTime updatedAt;

  FinancialObligation copyWith({
    List<String>? sourceEventIds,
    ObligationStatus? status,
    ObligationRecurrence? recurrence,
    String? linkedEventId,
    List<String>? reviewReasons,
    List<String>? evidence,
    DateTime? updatedAt,
  }) {
    return FinancialObligation(
      id: id,
      sourceEventIds: sourceEventIds ?? this.sourceEventIds,
      obligationType: obligationType,
      title: title,
      merchant: merchant,
      amount: amount,
      currency: currency,
      dueDate: dueDate,
      expectedTransactionDate: expectedTransactionDate,
      reminderDate: reminderDate,
      recurrence: recurrence ?? this.recurrence,
      accountMatch: accountMatch,
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      status: status ?? this.status,
      confidence: confidence,
      evidence: evidence ?? this.evidence,
      source: source,
      linkedEventId: linkedEventId ?? this.linkedEventId,
      reviewReasons: reviewReasons ?? this.reviewReasons,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
