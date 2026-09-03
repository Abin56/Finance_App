/**
 * Wire contract for `classifyFinancialSms` — mirrors the Flutter side's
 * `FinancialEventAiRequest`/`FinancialEventAiResult`
 * (lib/features/sms_inbox/domain/financial_event/financial_event_ai_provider.dart)
 * field-for-field. Keep the two in sync by hand; there is no shared codegen
 * between the Dart and TypeScript sides for this small a contract.
 */

export interface RegexEvidence {
  amount: number | null;
  direction: "debit" | "credit" | null;
  maskedAccount: string | null;
  referenceNumber: string | null;
  merchantGuess: string | null;
  categoryGuess: string;
  /** `ReminderDetector`'s own verdict — sent as context, not as an answer. */
  looksLikeReminder: boolean;
  /** `TransactionStatusSignals.detect().name` — same rationale. */
  transactionStatus: string;
}

export interface ClassifyRequest {
  /** Digit runs of 5+ already masked to their trailing 4 by the client. */
  redactedBody: string;
  senderBankName: string | null;
  regexEvidence: RegexEvidence;
  /** Log-correlation only — never persisted beyond function logs. */
  clientRequestId: string;
}

export interface ClassifyResponseConfidence {
  eventType: number;
  direction: number;
  amount: number;
  merchant: number;
  category: number;
  moneyMovement: number;
  transactionStatus: number;
}

/**
 * What *kind* of text a quoted `evidence` string is — mirrors the Dart
 * side's `AiEvidenceType` enum exactly. Plain substring grounding (is this
 * text really in the message?) cannot tell a VPA quote from a merchant-name
 * quote; this is the missing dimension that lets the client reject a
 * grounded-but-irrelevant quote (e.g. a real VPA "supporting" an invented
 * person's name) — see `AiClaimValidator` on the Dart side.
 */
export type AiEvidenceType =
  | "exact_text"
  | "vpa"
  | "merchant_name"
  | "provider_name"
  | "transaction_keyword"
  | "amount"
  | "account"
  | "contextual_phrase"
  | "unknown";

export interface ClassifyResponseEvidence {
  merchant: string | null;
  category: string | null;
  eventType: string | null;
  /**
   * What kind of text {@link ClassifyResponseEvidence.merchant} is. Field
   * name (not `merchantEvidenceType`'s own sibling shape) chosen to match
   * the Dart side's `FinancialEventAiResult.fromJson` reads verbatim —
   * keep both in sync by hand.
   */
  merchantEvidenceType: AiEvidenceType | null;
  /** What kind of text {@link ClassifyResponseEvidence.category} is. */
  categoryEvidenceType: AiEvidenceType | null;
  /**
   * What kind of text backs the top-level `paymentProvider` claim — there
   * is no separate provider evidence string; the client reuses `merchant`'s
   * quoted text as the provider's evidence too (see this file's Dart
   * mirror, `FinancialEventAiResult.evidenceProviderType`'s doc comment).
   */
  providerEvidenceType: AiEvidenceType | null;
}

export interface ClassifyResponse {
  eventType: string | null;
  direction: "debit" | "credit" | null;
  amount: number | null;
  merchant: string | null;
  category: string | null;
  paymentMethod: string | null;
  role: "standalone" | "originalCharge" | "linkedSettlement" | null;
  isLikelyRefundOrReversal: boolean;
  /**
   * Did money actually move? Independent of debit/credit keyword matching —
   * a reminder, a failed attempt, or a pending transaction must all read as
   * `false` regardless of how transaction-shaped the wording otherwise
   * looks. `null` means the model declined to answer (the client falls back
   * to its own deterministic `ReminderSignals`/`TransactionStatusSignals`
   * read in that case).
   */
  moneyMovement: boolean | null;
  /** One of: pending, success, failed, reversed, refunded, unknown. */
  transactionStatus: string | null;
  /**
   * Whether the resolved counterparty is a registered business or an
   * individual person (a P2P transfer) — mirrors the Dart side's
   * `MerchantType` enum exactly (`business` | `person` | `unknown`). This is
   * NOT a spending-category vertical (grocery/food-delivery/etc.) — that
   * distinction is already carried by `category`; conflating the two would
   * mean building a second, parallel category system, which this contract
   * deliberately avoids. Gated on the same evidence as `merchant` (see
   * `ClassifyResponseEvidence.merchant`) — a merchant type is meaningless
   * without a merchant to attach it to.
   */
  merchantType: "business" | "person" | "unknown" | null;
  /**
   * The rail/app that moved the money — mirrors the Dart side's
   * `PaymentProvider` enum exactly. Deliberately independent of `merchant`:
   * "Paid ₹800 using PhonePe to swiggy@upi" is `merchant: "Swiggy"`,
   * `paymentProvider: "phonePe"` — never the other way around, and never
   * conflated with the bank sending the SMS. Not gated on `merchant`'s
   * evidence — a payment provider can be explicitly named ("paid using
   * PhonePe") even when no counterparty is mentioned at all.
   */
  paymentProvider:
    | "phonePe"
    | "googlePay"
    | "paytm"
    | "amazonPay"
    | "bhim"
    | "cred"
    | "whatsappPay"
    | "bank"
    | "unknown"
    | null;
  confidence: ClassifyResponseConfidence;
  evidence: ClassifyResponseEvidence;
  /** One-sentence debug explanation — never shown verbatim to the end user. */
  reasoning: string;
}

/** The Cloud Function's own "could not classify" fallback — every field
 * null/zero but still schema-valid, so the client never needs a special
 * error path beyond a genuinely unreachable function. */
export const ALL_NULL_RESPONSE: ClassifyResponse = {
  eventType: null,
  direction: null,
  amount: null,
  merchant: null,
  category: null,
  paymentMethod: null,
  role: null,
  isLikelyRefundOrReversal: false,
  moneyMovement: null,
  transactionStatus: null,
  merchantType: null,
  paymentProvider: null,
  confidence: {
    eventType: 0,
    direction: 0,
    amount: 0,
    merchant: 0,
    category: 0,
    moneyMovement: 0,
    transactionStatus: 0,
  },
  evidence: {
    merchant: null,
    category: null,
    eventType: null,
    merchantEvidenceType: null,
    categoryEvidenceType: null,
    providerEvidenceType: null,
  },
  reasoning: "Classification unavailable.",
};
