/// What the AI is asked to classify — mirrors the Cloud Function's
/// `ClassifyRequest` contract 1:1 (see `functions/src/schema.ts`).
///
/// Deliberately sends a *redacted* body (digit runs of 5+ masked to their
/// last 4 by the caller before this request is built — see
/// `FinancialEventExtractor`), never the full raw SMS, and never the user's
/// account/card list — the AI has no visibility into which `Account`/
/// `CreditCardProfile` this message might belong to; that resolution stays
/// entirely on-device via `AccountCardMatcher`.
class FinancialEventAiRequest {
  const FinancialEventAiRequest({
    required this.redactedBody,
    required this.senderBankName,
    required this.regexAmount,
    required this.regexDirection,
    required this.regexMaskedAccount,
    required this.regexReferenceNumber,
    required this.regexMerchantGuess,
    required this.regexCategoryGuess,
    required this.regexLooksLikeReminder,
    required this.regexTransactionStatus,
    required this.clientRequestId,
  });

  final String redactedBody;
  final String? senderBankName;
  final double? regexAmount;

  /// `'debit'` / `'credit'` / null — sent as a plain string so the request
  /// payload matches the Cloud Function's JSON contract exactly.
  final String? regexDirection;
  final String? regexMaskedAccount;
  final String? regexReferenceNumber;
  final String? regexMerchantGuess;
  final String regexCategoryGuess;

  /// `ReminderDetector`'s own verdict, sent as context — the AI forms its
  /// own independent `moneyMovement`/`role` read, but seeing what the
  /// deterministic layer already concluded helps it agree/disagree
  /// explicitly rather than missing an ambiguous future-tense phrasing.
  final bool regexLooksLikeReminder;

  /// `TransactionStatusSignals.detect().name` — same rationale as
  /// [regexLooksLikeReminder].
  final String regexTransactionStatus;

  /// For log correlation only — never persisted server-side beyond function
  /// logs, and never shown to the user.
  final String clientRequestId;

  Map<String, dynamic> toJson() {
    return {
      'redactedBody': redactedBody,
      'senderBankName': senderBankName,
      'regexEvidence': {
        'amount': regexAmount,
        'direction': regexDirection,
        'maskedAccount': regexMaskedAccount,
        'referenceNumber': regexReferenceNumber,
        'merchantGuess': regexMerchantGuess,
        'categoryGuess': regexCategoryGuess,
        'looksLikeReminder': regexLooksLikeReminder,
        'transactionStatus': regexTransactionStatus,
      },
      'clientRequestId': clientRequestId,
    };
  }
}

/// Per-field confidence the AI self-reported (0.0-1.0) — mirrors
/// `ClassifyResponse.confidence`.
class FinancialEventAiFieldConfidences {
  const FinancialEventAiFieldConfidences({
    required this.eventType,
    required this.direction,
    required this.amount,
    required this.merchant,
    required this.category,
    this.moneyMovement = 0.0,
    this.transactionStatus = 0.0,
  });

  factory FinancialEventAiFieldConfidences.fromJson(Map<String, dynamic> json) {
    double read(String key) => (json[key] as num?)?.toDouble() ?? 0.0;
    return FinancialEventAiFieldConfidences(
      eventType: read('eventType'),
      direction: read('direction'),
      amount: read('amount'),
      merchant: read('merchant'),
      category: read('category'),
      moneyMovement: read('moneyMovement'),
      transactionStatus: read('transactionStatus'),
    );
  }

  final double eventType;
  final double direction;
  final double amount;
  final double merchant;
  final double category;
  final double moneyMovement;
  final double transactionStatus;
}

/// The AI's structured read of one SMS — mirrors `ClassifyResponse` 1:1.
/// Every nullable field here is null whenever the model (or the Cloud
/// Function's server-side schema validation) could not back it with
/// [evidenceMerchant]/[evidenceCategory]/[evidenceEventType] — "never invent
/// data" is enforced twice: once in the prompt, once in code (see
/// `functions/src/schema.ts`), and this class simply trusts that a non-null
/// value here already passed both checks.
class FinancialEventAiResult {
  const FinancialEventAiResult({
    required this.eventType,
    required this.direction,
    required this.amount,
    required this.merchant,
    required this.category,
    required this.paymentMethod,
    required this.role,
    required this.isLikelyRefundOrReversal,
    required this.confidences,
    this.moneyMovement,
    this.transactionStatus,
    this.merchantType,
    this.paymentProvider,
    this.evidenceMerchant,
    this.evidenceCategory,
    this.evidenceEventType,
    this.evidenceMerchantType,
    this.evidenceCategoryType,
    this.evidenceProviderType,
    this.reasoning,
    this.isFallback = false,
  });

  /// The Cloud Function's own "could not classify" structured response
  /// (LLM timeout/error handled server-side) — every field null/zero, but
  /// still a well-formed object so the extractor never needs a special error
  /// path beyond a genuinely unreachable function (see
  /// [FinancialEventAiProvider.classify] returning `null` for that case).
  const FinancialEventAiResult.allNull()
    : eventType = null,
      direction = null,
      amount = null,
      merchant = null,
      category = null,
      paymentMethod = null,
      role = null,
      isLikelyRefundOrReversal = false,
      confidences = const FinancialEventAiFieldConfidences(
        eventType: 0,
        direction: 0,
        amount: 0,
        merchant: 0,
        category: 0,
      ),
      moneyMovement = null,
      transactionStatus = null,
      merchantType = null,
      paymentProvider = null,
      evidenceMerchant = null,
      evidenceCategory = null,
      evidenceEventType = null,
      evidenceMerchantType = null,
      evidenceCategoryType = null,
      evidenceProviderType = null,
      reasoning = null,
      isFallback = true;

  factory FinancialEventAiResult.fromJson(Map<String, dynamic> json) {
    final evidence = json['evidence'] as Map<String, dynamic>? ?? const {};
    return FinancialEventAiResult(
      eventType: json['eventType'] as String?,
      direction: json['direction'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      merchant: json['merchant'] as String?,
      category: json['category'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
      role: json['role'] as String?,
      isLikelyRefundOrReversal:
          json['isLikelyRefundOrReversal'] as bool? ?? false,
      confidences: FinancialEventAiFieldConfidences.fromJson(
        json['confidence'] as Map<String, dynamic>? ?? const {},
      ),
      moneyMovement: json['moneyMovement'] as bool?,
      transactionStatus: json['transactionStatus'] as String?,
      merchantType: json['merchantType'] as String?,
      paymentProvider: json['paymentProvider'] as String?,
      evidenceMerchant: evidence['merchant'] as String?,
      evidenceCategory: evidence['category'] as String?,
      evidenceEventType: evidence['eventType'] as String?,
      evidenceMerchantType: evidence['merchantEvidenceType'] as String?,
      evidenceCategoryType: evidence['categoryEvidenceType'] as String?,
      evidenceProviderType: evidence['providerEvidenceType'] as String?,
      reasoning: json['reasoning'] as String?,
    );
  }

  /// Raw AI-provided event type name (`'payment'`, `'refund'`, ...) — mapped
  /// to [FinancialEventType] by the extractor, not here, so this class stays
  /// a plain mirror of the wire contract.
  final String? eventType;
  final String? direction;
  final double? amount;
  final String? merchant;

  /// Free-text category *name* — resolved against the user's real
  /// categories client-side by `CategoryResolver`; the Cloud Function has no
  /// visibility into the user's category list.
  final String? category;
  final String? paymentMethod;
  final String? role;
  final bool isLikelyRefundOrReversal;
  final FinancialEventAiFieldConfidences confidences;

  /// The AI's own independent read of whether money actually moved — null
  /// means it declined to answer (treated the same as any other abstained
  /// field: falls back to the deterministic `ReminderSignals`/
  /// `TransactionStatusSignals` read). Reconciled against that deterministic
  /// signal as a hard-fact field in `FinancialEventExtractor`, with the more
  /// conservative (`false`) value winning on disagreement — see
  /// `FinancialEvent.moneyMovement`'s doc comment for why.
  final bool? moneyMovement;

  /// Raw AI-provided status name (`'pending'`, `'failed'`, `'success'`, ...)
  /// — mapped to [TransactionStatus] by the extractor.
  final String? transactionStatus;

  /// Raw AI-provided merchant type name (`'business'`/`'person'`) — only
  /// ever trusted by `MerchantIdentityResolver` alongside [evidenceMerchant]
  /// (the same evidence backs both the name and its type).
  final String? merchantType;

  /// Raw AI-provided payment-provider name (`'phonePe'`, `'googlePay'`,
  /// ...) — never trusted over an explicit deterministic phrase match, see
  /// `PaymentProviderResolver`.
  final String? paymentProvider;

  final String? evidenceMerchant;
  final String? evidenceCategory;
  final String? evidenceEventType;

  /// Raw `AiEvidenceType` name (`'vpa'`, `'merchant_name'`, ...) describing
  /// *what kind* of text [evidenceMerchant] is — see `AiClaimValidator`,
  /// which uses this to reject e.g. a bare VPA quote "supporting" an
  /// invented person's name, something plain substring grounding alone
  /// cannot catch. Null is treated as [AiEvidenceType.unknown] — the
  /// weakest tier, never enough alone for an identity claim.
  final String? evidenceMerchantType;

  /// Same idea as [evidenceMerchantType], for [evidenceCategory].
  final String? evidenceCategoryType;

  /// Same idea as [evidenceMerchantType], for the AI's [paymentProvider]
  /// claim specifically (there is no separate `evidenceProvider` text —
  /// see `AiClaimValidator.validatePaymentProvider`, which reuses
  /// [evidenceMerchant] as the quoted text and this field as its type).
  final String? evidenceProviderType;

  /// One-sentence debug explanation — never shown verbatim to the end user.
  final String? reasoning;

  /// True when this result came from [FinancialEventAiResult.allNull] (a
  /// server-side fallback) rather than a genuine model classification.
  final bool isFallback;
}

/// Classifies one SMS's redacted content + regex evidence into a structured
/// [FinancialEventAiResult]. Implementations must **never throw** —
/// `classify` returns `null` on any failure (network, timeout, malformed
/// response), which `FinancialEventExtractor` treats as "the AI abstained,"
/// falling back to regex-only evidence. This is what keeps a flaky or
/// offline AI call from ever breaking an SMS scan (see the SMS AI rebuild
/// plan §26, "offline/API failure behavior").
///
/// Kept as an interface — not just one concrete implementation — so the
/// provider (which Cloud Function, which model, or a local no-op) can be
/// swapped without touching anything else in the pipeline.
abstract class FinancialEventAiProvider {
  Future<FinancialEventAiResult?> classify(FinancialEventAiRequest request);
}

/// Always abstains — used when the user has disabled AI processing, or as
/// the default in contexts where no real provider is configured. The
/// extractor's regex-only fallback path is exercised identically whether
/// this returns null because AI is disabled or because a real provider
/// failed, which is exactly the point: "AI unavailable" is one code path,
/// not two.
class NoopFinancialEventAiProvider implements FinancialEventAiProvider {
  const NoopFinancialEventAiProvider();

  @override
  Future<FinancialEventAiResult?> classify(
    FinancialEventAiRequest request,
  ) async => null;
}
