import { z } from "zod";
import { ALL_NULL_RESPONSE, ClassifyResponse } from "./types";

export const RegexEvidenceSchema = z.object({
  amount: z.number().nullable(),
  direction: z.enum(["debit", "credit"]).nullable(),
  maskedAccount: z.string().nullable(),
  referenceNumber: z.string().nullable(),
  merchantGuess: z.string().nullable(),
  categoryGuess: z.string(),
  looksLikeReminder: z.boolean(),
  transactionStatus: z.string(),
});

export const ClassifyRequestSchema = z.object({
  redactedBody: z.string().min(1).max(2000),
  senderBankName: z.string().nullable(),
  regexEvidence: RegexEvidenceSchema,
  clientRequestId: z.string().min(1).max(200),
});

const EvidenceTypeSchema = z
  .enum([
    "exact_text",
    "vpa",
    "merchant_name",
    "provider_name",
    "transaction_keyword",
    "amount",
    "account",
    "contextual_phrase",
    "unknown",
  ])
  .nullable()
  .optional();

const RawEvidenceSchema = z.object({
  merchant: z.string().nullable(),
  category: z.string().nullable(),
  eventType: z.string().nullable(),
  // Optional/nullable for the same backward-compatibility reason as
  // merchantType/paymentProvider below — an older fixture/test without
  // these still parses.
  merchantEvidenceType: EvidenceTypeSchema,
  categoryEvidenceType: EvidenceTypeSchema,
  providerEvidenceType: EvidenceTypeSchema,
});

/**
 * The model's raw tool-call output, before the "never invent without
 * evidence" enforcement below. Deliberately permissive on string length —
 * the enforcement, not a length cap, is what keeps this trustworthy.
 */
const RawModelOutputSchema = z.object({
  eventType: z.string().nullable(),
  direction: z.enum(["debit", "credit"]).nullable(),
  amount: z.number().nullable(),
  merchant: z.string().nullable(),
  category: z.string().nullable(),
  paymentMethod: z.string().nullable(),
  role: z.enum(["standalone", "originalCharge", "linkedSettlement"]).nullable(),
  isLikelyRefundOrReversal: z.boolean(),
  moneyMovement: z.boolean().nullable(),
  transactionStatus: z
    .enum(["pending", "success", "failed", "reversed", "refunded", "unknown"])
    .nullable(),
  // Optional (not just nullable) so a raw payload that predates these two
  // fields — an older cached fixture, a hand-written test — still parses
  // instead of falling back to ALL_NULL_RESPONSE wholesale; a real model
  // response always includes them, since both are in the tool's `required`
  // list (see prompt.ts).
  merchantType: z.enum(["business", "person", "unknown"]).nullable().optional(),
  paymentProvider: z
    .enum([
      "phonePe",
      "googlePay",
      "paytm",
      "amazonPay",
      "bhim",
      "cred",
      "whatsappPay",
      "bank",
      "unknown",
    ])
    .nullable()
    .optional(),
  confidence: z.object({
    eventType: z.number().min(0).max(1),
    direction: z.number().min(0).max(1),
    amount: z.number().min(0).max(1),
    merchant: z.number().min(0).max(1),
    category: z.number().min(0).max(1),
    moneyMovement: z.number().min(0).max(1),
    transactionStatus: z.number().min(0).max(1),
  }),
  evidence: RawEvidenceSchema,
  reasoning: z.string(),
});

/**
 * A quoted piece of evidence proves it is *real text from the message*
 * (grounding, enforced below via the non-empty checks); it does not by
 * itself prove that text *supports* the specific claim it's attached to.
 * Mirrors the Dart side's `AiClaimValidator` — kept in sync by hand, same
 * as every other piece of this contract. A VPA quote never establishes a
 * merchant/category claim; a provider-name quote establishes a provider
 * claim but never a merchant/category claim.
 */
function evidenceTypeSupportsIdentityOrCategoryClaim(
  type: z.infer<typeof EvidenceTypeSchema>,
): boolean {
  return (
    type === "exact_text" ||
    type === "merchant_name" ||
    type === "contextual_phrase" ||
    // Absent entirely (as opposed to an explicit weak type) is treated
    // leniently for backward compatibility — see the Dart mirror's
    // identical rationale in `MerchantResolver.resolve`.
    type === undefined ||
    type === null
  );
}

/**
 * Validates and sanitizes the model's raw output into a trustworthy
 * {@link ClassifyResponse}. This is the second, code-level enforcement of
 * "never invent data" (the first is the prompt instruction in prompt.ts):
 * any of merchant/category/eventType that is non-null but whose matching
 * `evidence` entry is empty/missing is coerced to null here, regardless of
 * what the model claimed. A response that fails schema validation entirely
 * (malformed JSON, wrong types) falls back to {@link ALL_NULL_RESPONSE}
 * rather than propagating a parse error to the client.
 *
 * Phase 5 adds a second dimension on top of plain grounding: even when the
 * quoted evidence text genuinely occurs in the message, a
 * `merchantEvidenceType`/`categoryEvidenceType` of `"vpa"` or
 * `"provider_name"` (etc.) is not strong enough to support a merchant or
 * category claim — see {@link evidenceTypeSupportsIdentityOrCategoryClaim}.
 * This mirrors `AiClaimValidator` on the Dart side, which re-checks the
 * same rule client-side (the two are independent, defense-in-depth layers,
 * not a single point of trust).
 */
export function sanitizeModelOutput(raw: unknown): ClassifyResponse {
  const parsed = RawModelOutputSchema.safeParse(raw);
  if (!parsed.success) return ALL_NULL_RESPONSE;

  const data = parsed.data;

  const merchant =
    data.evidence.merchant &&
    data.evidence.merchant.trim().length > 0 &&
    evidenceTypeSupportsIdentityOrCategoryClaim(data.evidence.merchantEvidenceType)
      ? data.merchant
      : null;
  const category =
    data.evidence.category &&
    data.evidence.category.trim().length > 0 &&
    evidenceTypeSupportsIdentityOrCategoryClaim(data.evidence.categoryEvidenceType)
      ? data.category
      : null;
  const eventType =
    data.evidence.eventType && data.evidence.eventType.trim().length > 0
      ? data.eventType
      : null;
  // A merchant *type* only means something once a merchant itself survived
  // the evidence gate above — same rationale as `category`/`eventType`,
  // reusing `merchant`'s own evidence rather than inventing a second
  // evidence slot the Dart side doesn't parse (see `ClassifyResponseEvidence`).
  const merchantType = merchant ? (data.merchantType ?? null) : null;
  // Deliberately NOT gated on merchant evidence — "paid using PhonePe" is
  // valid provider evidence with no counterparty named at all. Gated
  // instead on its own evidence type: only an explicit provider-name quote
  // establishes a provider claim (a bare VPA is a deterministic *hint*,
  // handled entirely client-side by `PaymentProviderResolver`, never an AI
  // assertion).
  const paymentProvider =
    evidenceTypeSupportsProviderClaim(data.evidence.providerEvidenceType)
      ? (data.paymentProvider ?? null)
      : null;

  return {
    eventType,
    direction: data.direction,
    amount: data.amount,
    merchant,
    category,
    paymentMethod: data.paymentMethod,
    role: data.role,
    isLikelyRefundOrReversal: data.isLikelyRefundOrReversal,
    moneyMovement: data.moneyMovement,
    transactionStatus: data.transactionStatus,
    merchantType,
    paymentProvider,
    confidence: data.confidence,
    evidence: {
      merchant: merchant ? data.evidence.merchant : null,
      category: category ? data.evidence.category : null,
      eventType: eventType ? data.evidence.eventType : null,
      merchantEvidenceType: merchant
        ? (data.evidence.merchantEvidenceType ?? null)
        : null,
      categoryEvidenceType: category
        ? (data.evidence.categoryEvidenceType ?? null)
        : null,
      providerEvidenceType: paymentProvider
        ? (data.evidence.providerEvidenceType ?? null)
        : null,
    },
    reasoning: data.reasoning,
  };
}

/**
 * Only an explicit provider-name quote (or no type specified at all, kept
 * lenient for backward compatibility — same rationale as
 * {@link evidenceTypeSupportsIdentityOrCategoryClaim}) establishes a
 * `paymentProvider` claim.
 */
function evidenceTypeSupportsProviderClaim(
  type: z.infer<typeof EvidenceTypeSchema>,
): boolean {
  return type === "provider_name" || type === undefined || type === null;
}
