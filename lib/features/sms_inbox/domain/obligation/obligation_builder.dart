import '../financial_event/field_confidence.dart';
import '../financial_event/financial_event_type.dart';
import '../financial_event/payment_method.dart';
import '../financial_event/transaction_status.dart';
import 'financial_obligation.dart';
import 'obligation_classifier.dart';
import 'obligation_date_resolver.dart';
import 'obligation_recurrence.dart';
import 'obligation_semantic_bucket.dart';
import 'obligation_source.dart';
import 'obligation_status.dart';
import 'obligation_type.dart';

/// The single entry point that can produce a [FinancialObligation] — and
/// the only place in this engine that does. [build] returns `null`
/// whenever [ObligationClassifier] does not resolve to an outstanding
/// bucket (reminder/upcoming/due), which is the concrete implementation of
/// Safety rule 1 ("a reminder must never become a completed transaction"):
/// a completed/pending/failed/reversed/refund/unknown read simply never
/// reaches obligation construction at all.
class ObligationBuilder {
  const ObligationBuilder({this.classifier = const ObligationClassifier()});

  final ObligationClassifier classifier;

  /// Builds a [FinancialObligation] from one financial-shaped SMS/event, or
  /// `null` if [body] does not describe an outstanding obligation.
  ///
  /// [smsReceivedAt] is used *only* as the anchor for resolving relative
  /// dates ("tomorrow", "in 3 days") — it is never itself used as the
  /// obligation's due date (see [ObligationDateResolver]'s doc comment and
  /// Safety rule 11).
  FinancialObligation? build({
    required String id,
    required String sourceEventId,
    required String body,
    required DateTime smsReceivedAt,
    FieldConfidence<double> amount = const FieldConfidence<double>.unknown(),
    FieldConfidence<String> merchant = const FieldConfidence<String>.unknown(),
    FieldConfidence<String> accountMatch =
        const FieldConfidence<String>.unknown(),
    FieldConfidence<PaymentMethod> paymentMethod =
        const FieldConfidence<PaymentMethod>.unknown(),
    String? referenceNumber,
    TransactionStatus? transactionStatus,
    bool? moneyMovement,
    FinancialEventType? eventType,
    DateTime? now,
  }) {
    final classification = classifier.classify(
      body: body,
      transactionStatus: transactionStatus,
      moneyMovement: moneyMovement,
      eventType: eventType,
    );
    if (!classification.bucket.isOutstanding) return null;

    final resolvedDate = ObligationDateResolver.resolve(
      body,
      referenceDate: smsReceivedAt,
    );
    final createdAt = now ?? smsReceivedAt;

    final reviewReasons = <String>[
      if (amount.value == null)
        'Amount could not be determined from the message.',
      if (!resolvedDate.isKnown)
        'No due/scheduled date could be resolved from the message.',
      if (merchant.value == null)
        'Merchant/provider could not be determined from the message.',
    ];

    return FinancialObligation(
      id: id,
      sourceEventIds: [sourceEventId],
      obligationType: classification.obligationType,
      title: _titleFor(classification.obligationType, merchant.value),
      merchant: merchant,
      amount: amount,
      dueDate: resolvedDate,
      expectedTransactionDate:
          resolvedDate.kind == ObligationDateKind.scheduledDebitDate
          ? resolvedDate
          : null,
      recurrence: ObligationRecurrence.singleObservation(smsReceivedAt),
      accountMatch: accountMatch,
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      status: _initialStatus(
        classification.bucket,
        resolvedDate,
        smsReceivedAt,
      ),
      confidence: classification.confidence,
      evidence: [
        classification.reason,
        if (resolvedDate.evidence != null)
          'Date evidence: "${resolvedDate.evidence}" -> ${resolvedDate.kind.name}',
      ],
      source: ObligationSource.smsDetected,
      reviewReasons: reviewReasons,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  String _titleFor(ObligationType type, String? merchant) {
    final label = type.label;
    if (merchant == null || merchant.isEmpty) return label;
    return '$merchant — $label';
  }

  ObligationStatus _initialStatus(
    ObligationSemanticBucket bucket,
    ResolvedObligationDate resolvedDate,
    DateTime referenceDate,
  ) {
    if (!resolvedDate.isKnown) return ObligationStatus.detected;
    final due = resolvedDate.value!;
    if (due.isAfter(referenceDate)) return ObligationStatus.upcoming;
    return ObligationStatus.due;
  }
}
