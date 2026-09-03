import '../sms_confidence_scorer.dart';
import '../sms_transaction_direction.dart';
import 'automation_action.dart';
import 'field_confidence.dart';
import 'financial_event_role.dart';
import 'financial_event_status.dart';
import 'financial_event_type.dart';
import 'merchant_type.dart';
import 'payment_method.dart';
import 'payment_provider.dart';
import 'transaction_status.dart';

/// The hybrid engine's reconciled read of what a financial SMS actually
/// describes — one [FinancialEvent] per real-world transaction, potentially
/// built from and linked to multiple [SmsInboxItem]s (see
/// `FinancialEventEvidenceLink`, `sms_financial_event_links`).
///
/// Produced by `FinancialEventExtractor` (regex + AI reconciliation) and
/// `TransactionMatcher` (identity/linking against existing events), scored
/// by `FinancialEventConfidenceEngine`, and decided on by `AutomationPolicy`
/// — but this phase, [automationAction] is a *recommendation only*: nothing
/// in the pipeline executes it. Every event surfaces through the existing
/// manual `SmsConvertSheet`/`SmsConversionRouter` flow for the user to
/// convert, ignore, or leave pending, exactly as `TransactionCandidate`
/// already does today. See `AutomationAction`'s doc comment.
///
/// Reuses [ConfidenceLevel] (`sms_confidence_scorer.dart`) and
/// [SmsTransactionDirection] rather than inventing parallel concepts that
/// already exist elsewhere in this feature.
class FinancialEvent {
  const FinancialEvent({
    required this.id,
    required this.primarySmsItemId,
    required this.eventType,
    required this.role,
    required this.status,
    required this.direction,
    required this.amount,
    required this.merchant,
    required this.category,
    required this.paymentMethod,
    required this.accountMatch,
    required this.moneyMovement,
    required this.transactionStatus,
    required this.eventDate,
    required this.overallConfidence,
    required this.confidenceLevel,
    required this.automationAction,
    required this.needsReview,
    required this.reviewReasons,
    required this.createdAt,
    this.matchedCardId,
    this.normalizedSender,
    this.referenceNumber,
    this.linkedTransactionId,
    this.linkedEventId,
    this.subcategory,
    this.isOwnAccountTransfer = false,
    this.paymentProvider = const FieldConfidence<PaymentProvider>.unknown(),
    this.merchantType = const FieldConfidence<MerchantType>.unknown(),
    this.aiRawResponse,
    this.aiModelVersion,
  });

  final String id;

  /// The [SmsInboxItem.id] this event was first built from — see
  /// `FinancialEventEvidenceLink` for every SMS (this one included)
  /// contributing to it.
  final String primarySmsItemId;

  final FinancialEventType eventType;
  final FinancialEventRole role;
  final FinancialEventStatus status;
  final SmsTransactionDirection direction;

  final FieldConfidence<double> amount;
  final FieldConfidence<String> merchant;

  /// Resolves to an existing `Category.id` — never an invented category, see
  /// `CategoryResolver`.
  final FieldConfidence<String> category;

  final FieldConfidence<PaymentMethod> paymentMethod;

  /// Resolves to an existing `Account.id` (see `AccountMatchResult`). Never
  /// touched by the AI provider — the account list is never sent off-device,
  /// so this field's [FieldConfidence.source] is always
  /// [EvidenceSource.regexOnly] or [EvidenceSource.none].
  final FieldConfidence<String> accountMatch;

  /// Whether money actually moved — independent of debit/credit keyword
  /// matching, per the SMS AI rebuild plan's central distinction: "Your EMI
  /// of ₹8,500 is due tomorrow" and "₹8,500 debited towards your EMI" both
  /// contain the same amount/keyword shape, but only the second one is real
  /// money movement. Reconciled (as a hard-fact field, most-conservative-
  /// wins on disagreement — see `FinancialEventExtractor`) between
  /// `ReminderSignals`/`TransactionStatusSignals` (deterministic) and the
  /// AI's own independent read. `value == false` always means "do not treat
  /// this as spending/income" — a reminder, a failed attempt, and a pending
  /// transaction all share this regardless of how transaction-shaped their
  /// wording otherwise looks.
  final FieldConfidence<bool> moneyMovement;

  /// The real-world lifecycle status this message describes — see
  /// [TransactionStatus]. Reconciled the same hard-fact way as
  /// [moneyMovement].
  final FieldConfidence<TransactionStatus> transactionStatus;

  /// Set only when the resolved [accountMatch] is a credit card — mirrors
  /// `TransactionCandidate.matchedCardId`/`AccountMatchResult.matchedCardId`.
  final String? matchedCardId;

  /// `BankSenderMatcher.normalize()` of the originating SMS's sender —
  /// stored purely as a `TransactionMatcher` query signal (see
  /// `FinancialEventDao.findBySenderAmountWindow`), never shown in the UI.
  final String? normalizedSender;

  final DateTime eventDate;

  /// 0.0-1.0, from `FinancialEventConfidenceEngine`.
  final double overallConfidence;
  final ConfidenceLevel confidenceLevel;

  /// What `AutomationPolicy` recommends — computed and stored, never
  /// auto-executed this phase. See [AutomationAction]'s doc comment.
  final AutomationAction automationAction;

  final bool needsReview;

  /// Human-readable reasons, shown verbatim to the reviewing user — same
  /// transparency principle `SmsConfidenceResult.reasons`/
  /// `TransactionCandidate.reviewReasons` already follow.
  final List<String> reviewReasons;

  final DateTime createdAt;

  final String? referenceNumber;

  /// Set once the user manually converts this event via `SmsConvertSheet` —
  /// mirrors `SmsInboxItem.linkedEntityId`'s "only after the real save
  /// succeeded" invariant.
  final String? linkedTransactionId;

  /// Set when [role] is [FinancialEventRole.linkedSettlement] — points at the
  /// [FinancialEvent.id] of the [FinancialEventRole.originalCharge] this
  /// event resolves (a refund/reversal/credit-card-bill-payment).
  final String? linkedEventId;

  /// Display-only, more granular than [category] (e.g. "Food Delivery" vs.
  /// the user's own "Food" category) — populated only when the AI's category
  /// guess doesn't cleanly match an existing `Category.name`. Never written
  /// to a real `Transaction`/`Category`, which have no subcategory concept.
  final String? subcategory;

  /// Deterministic-only (never AI-influenced, since the AI never sees the
  /// user's account list) — set when the message's own text mentions a
  /// second last-4 that also belongs to one of the user's other accounts,
  /// i.e. a transfer between the user's own accounts rather than to an
  /// external payee. See `AccountCardMatcher.isKnownLastFour`.
  final bool isOwnAccountTransfer;

  /// The rail/app that moved the money (PhonePe, Google Pay, ...) —
  /// deliberately separate from [merchant] (the counterparty being paid).
  /// See `PaymentProvider`'s doc comment and `PaymentProviderResolver`.
  final FieldConfidence<PaymentProvider> paymentProvider;

  /// Whether the resolved [merchant] is a business or a person — see
  /// `MerchantIdentity`/`MerchantIdentityResolver`, which computes the
  /// richer identity this (and [merchant]) are distilled from.
  final FieldConfidence<MerchantType> merchantType;

  /// The AI provider's raw JSON response, kept for debugging/audit — never
  /// shown to the end user verbatim (see `FinancialEventAiResult.reasoning`).
  final String? aiRawResponse;
  final String? aiModelVersion;

  FinancialEvent copyWith({
    FinancialEventRole? role,
    FinancialEventStatus? status,
    double? overallConfidence,
    ConfidenceLevel? confidenceLevel,
    AutomationAction? automationAction,
    bool? needsReview,
    String? linkedTransactionId,
    String? linkedEventId,
  }) {
    return FinancialEvent(
      id: id,
      primarySmsItemId: primarySmsItemId,
      eventType: eventType,
      role: role ?? this.role,
      status: status ?? this.status,
      direction: direction,
      amount: amount,
      merchant: merchant,
      category: category,
      paymentMethod: paymentMethod,
      accountMatch: accountMatch,
      moneyMovement: moneyMovement,
      transactionStatus: transactionStatus,
      matchedCardId: matchedCardId,
      normalizedSender: normalizedSender,
      eventDate: eventDate,
      overallConfidence: overallConfidence ?? this.overallConfidence,
      confidenceLevel: confidenceLevel ?? this.confidenceLevel,
      automationAction: automationAction ?? this.automationAction,
      needsReview: needsReview ?? this.needsReview,
      reviewReasons: reviewReasons,
      createdAt: createdAt,
      referenceNumber: referenceNumber,
      linkedTransactionId: linkedTransactionId ?? this.linkedTransactionId,
      linkedEventId: linkedEventId ?? this.linkedEventId,
      subcategory: subcategory,
      isOwnAccountTransfer: isOwnAccountTransfer,
      paymentProvider: paymentProvider,
      merchantType: merchantType,
      aiRawResponse: aiRawResponse,
      aiModelVersion: aiModelVersion,
    );
  }
}
