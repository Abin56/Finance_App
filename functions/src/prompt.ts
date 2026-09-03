import { ClassifyRequest } from "./types";

/**
 * The tool (forced JSON-output) schema handed to the model — mirrors
 * `RawModelOutputSchema` in schema.ts. Using Anthropic's tool-use forces
 * structured output instead of relying on the model to format free-form
 * JSON correctly.
 */
export const CLASSIFY_TOOL_NAME = "classify_financial_sms";

export const CLASSIFY_TOOL_INPUT_SCHEMA = {
  type: "object",
  properties: {
    eventType: {
      type: ["string", "null"],
      description:
        "One of: payment, receipt, transfer, refund, reversal, creditCardBill, loanEmi, cashWithdrawal, cashDeposit, cashback, salary, interest, fee, recharge, billPayment, reminder, unknown. Null if you cannot tell.",
    },
    direction: { type: ["string", "null"], enum: ["debit", "credit", null] },
    amount: { type: ["number", "null"] },
    merchant: {
      type: ["string", "null"],
      description:
        "The merchant/person/business name (the counterparty — a business OR a real person's name for a P2P transfer), ONLY if explicitly present or clearly inferable from the message text — never a guess.",
    },
    category: {
      type: ["string", "null"],
      description:
        "A free-text spending category name (e.g. 'Food & Dining', 'Transport'), only if you have real evidence for it.",
    },
    paymentMethod: {
      type: ["string", "null"],
      enum: [
        "upi",
        "debitCard",
        "creditCard",
        "netBanking",
        "neftRtgsImps",
        "cash",
        "wallet",
        "unknown",
        null,
      ],
    },
    role: {
      type: ["string", "null"],
      enum: ["standalone", "originalCharge", "linkedSettlement", null],
      description:
        "originalCharge = a charge that a later payment/refund will resolve (e.g. a credit card purchase). linkedSettlement = this message IS that later resolution (a credit card bill payment, a refund, a reversal). standalone = neither.",
    },
    isLikelyRefundOrReversal: { type: "boolean" },
    moneyMovement: {
      type: ["boolean", "null"],
      description:
        "Did money actually move, right now, as described by this exact message? false for a reminder/upcoming-due notice, a failed attempt, or a pending/processing transaction — even if the message contains words like 'debited' or a valid amount. true only for a completed transaction, refund, or reversal. Null only if you genuinely cannot tell.",
    },
    transactionStatus: {
      type: ["string", "null"],
      enum: [
        "pending",
        "success",
        "failed",
        "reversed",
        "refunded",
        "unknown",
        null,
      ],
    },
    merchantType: {
      type: ["string", "null"],
      enum: ["business", "person", "unknown", null],
      description:
        "Is the counterparty in `merchant` a registered business or an individual person (a P2P transfer)? This is NOT a spending category (do not answer with things like 'food delivery' or 'grocery' here — that belongs in `category`). Only set this alongside a non-null `merchant` backed by real evidence; 'unknown' (or null) is correct whenever you cannot tell, which is most of the time for a bare VPA/phone number.",
    },
    paymentProvider: {
      type: ["string", "null"],
      enum: [
        "phonePe",
        "googlePay",
        "paytm",
        "amazonPay",
        "bhim",
        "cred",
        "whatsappPay",
        "bank",
        "unknown",
        null,
      ],
      description:
        "The UPI app/rail that moved the money — NEVER the merchant, and NEVER the bank that sent this SMS. 'Paid Rs.800 using PhonePe to swiggy@upi' is merchant='Swiggy' (a business), paymentProvider='phonePe' (the app) — not the other way around. Only set this from an explicit phrase ('using PhonePe', 'via Google Pay', 'through Paytm') or an unambiguous VPA handle; a bare 'paid to someone@bank' with no such phrase must be 'unknown', never guessed from the bank name alone. 'bank' means a plain bank-rail transaction (NEFT/IMPS/card) with no third-party UPI app named.",
    },
    confidence: {
      type: "object",
      properties: {
        eventType: { type: "number" },
        direction: { type: "number" },
        amount: { type: "number" },
        merchant: { type: "number" },
        category: { type: "number" },
        moneyMovement: { type: "number" },
        transactionStatus: { type: "number" },
      },
      required: [
        "eventType",
        "direction",
        "amount",
        "merchant",
        "category",
        "moneyMovement",
        "transactionStatus",
      ],
    },
    evidence: {
      type: "object",
      description:
        "For each of merchant/category/eventType that you set a non-null value for above, quote the exact substring from the message that justifies it. If you cannot quote evidence, the corresponding value above MUST be null. `merchant`'s evidence also backs `merchantType` — there is no separate evidence slot for it, so a non-null `merchantType` requires a non-null `merchant` with real evidence too. `paymentProvider` does not need merchant evidence, but does need its own `providerEvidenceType`.",
      properties: {
        merchant: { type: ["string", "null"] },
        category: { type: ["string", "null"] },
        eventType: { type: ["string", "null"] },
        merchantEvidenceType: {
          type: ["string", "null"],
          enum: [
            "exact_text",
            "vpa",
            "merchant_name",
            "provider_name",
            "transaction_keyword",
            "amount",
            "account",
            "contextual_phrase",
            "unknown",
            null,
          ],
          description:
            "What KIND of text `evidence.merchant` is — this matters as much as the quote itself. Use 'merchant_name' when the message directly names the business/person (e.g. 'to Swiggy', 'trf to Rahul Kumar'). Use 'vpa' when your only evidence is a VPA string (e.g. 'someone@oksbi') — this is honest and correct, but a VPA never proves who it belongs to, so tagging it 'vpa' is what keeps your guess from being wrongly trusted as a verified identity; do not upgrade it to 'merchant_name' just because you have a hunch about who the VPA might belong to. Use 'contextual_phrase' for weaker descriptive evidence (e.g. 'the store near the station'). NEVER use 'provider_name' here — a payment app is not a merchant.",
        },
        categoryEvidenceType: {
          type: ["string", "null"],
          enum: [
            "exact_text",
            "vpa",
            "merchant_name",
            "provider_name",
            "transaction_keyword",
            "amount",
            "account",
            "contextual_phrase",
            "unknown",
            null,
          ],
          description:
            "What KIND of text `evidence.category` is. 'merchant_name' (the category follows obviously from a named merchant) and 'contextual_phrase' (e.g. 'a restaurant order', 'monthly subscription') are the normal cases. NEVER use 'provider_name' or 'vpa' here — the payment rail/app a transaction travelled on is not a spending category, and a bare VPA carries no category information at all.",
        },
        providerEvidenceType: {
          type: ["string", "null"],
          enum: [
            "exact_text",
            "vpa",
            "merchant_name",
            "provider_name",
            "transaction_keyword",
            "amount",
            "account",
            "contextual_phrase",
            "unknown",
            null,
          ],
          description:
            "What KIND of text backs your `paymentProvider` claim (reuses `evidence.merchant`'s text if that's where you saw it, or describe separately in reasoning). Only 'provider_name' (an explicit phrase like 'using PhonePe') is trusted — a VPA handle alone is not something you should assert a provider from; that weak inference is handled separately, deterministically, by this app.",
        },
      },
      required: [
        "merchant",
        "category",
        "eventType",
        "merchantEvidenceType",
        "categoryEvidenceType",
        "providerEvidenceType",
      ],
    },
    reasoning: {
      type: "string",
      description: "One short sentence, for internal debugging only.",
    },
  },
  required: [
    "eventType",
    "direction",
    "amount",
    "merchant",
    "category",
    "paymentMethod",
    "role",
    "isLikelyRefundOrReversal",
    "moneyMovement",
    "transactionStatus",
    "merchantType",
    "paymentProvider",
    "confidence",
    "evidence",
    "reasoning",
  ],
} as const;

export const SYSTEM_PROMPT = `You are a financial SMS classifier for an Indian personal finance app.

Your job is to understand what a bank/UPI/payment SMS actually describes — not to match it against a template. The question you are answering is "what actually happened financially in this message," not "which bank SMS template does this resemble."

Critical rules:
1. moneyMovement is the single most important field you set. It must be false for a reminder ("your EMI is due tomorrow"), a failed attempt, or a pending/processing transaction — even when the message uses words like "debited" or states a perfectly valid amount. Future-tense wording ("will be debited", "is due", "is scheduled to be charged") is a reminder, not a completed transaction, regardless of what verb follows. It is true for a completed payment/receipt, and also true for a refund or reversal (those are real, if inverse, money movements). When in doubt, prefer false — the cost of wrongly suppressing a real transaction (a human still reviews it) is far lower than the cost of wrongly implying money moved when it did not.
2. Distinguish a refund or reversal from a fresh charge.
3. Distinguish a credit card PURCHASE (role=originalCharge) from a credit card BILL PAYMENT (role=linkedSettlement) — a purchase is charged to the card; a bill payment pays off the card's balance from a bank account.
4. NEVER invent any of the following unless you can quote the exact substring that justifies it: a merchant name, a person's name, a spending category, an account number, a transaction/reference ID, or a date. This app extracts account numbers, transaction/reference IDs, and dates itself via deterministic parsing — you are never asked for them and must not include them in free-text fields like "reasoning" beyond what you were given as context. For merchant/category/eventType specifically: if you cannot point to the exact substring, return null for that field and leave the matching evidence field null too. Guessing a plausible-sounding merchant/category when the text doesn't support it is one of the worst mistakes you can make here — a wrong category silently misfiles a real person's spending, and a wrong "reminder resolved" claim can hide a transaction from someone's records entirely. This also applies to OTPs/CVVs/PINs/phone numbers or any other personal data — you are never asked for these and must never surface them anywhere in your response, even inside "reasoning".
5. You are also given this app's own regex-based reading of the message (amount, direction, masked account, reference number, a coarse category guess, whether it already looks like a reminder, and a coarse transaction-status read) as context — you do not need to re-derive these, but your own independent read is what gets compared against them for a final decision, so answer as if the regex evidence did not exist. Where you and the regex evidence disagree, that disagreement gets surfaced for a human to resolve — you are not the final authority, so answer honestly rather than trying to "agree" with the regex hints. Amount, direction, account, and reference number in particular are hard facts this app already extracted deterministically — you are not the source of truth for them and must never contradict them just to sound more confident.
6. Every confidence value is your own 0.0-1.0 self-assessment of that specific field, not a restatement of how "certain" you feel overall.
7. You are never told which of the user's real accounts/cards/categories this message might belong to, and must not guess at that either — resolving to a real account/category is handled entirely outside your response.
8. "merchant" is WHO was paid; "paymentProvider" is WHAT app/rail moved the money; they are never the same thing, and neither is ever the bank that sent this SMS. "Paid Rs.800 using PhonePe to swiggy@upi" is merchant="Swiggy", paymentProvider="phonePe" — NOT merchant="PhonePe". "Rs.500 paid to amazon@upi through Google Pay" is merchant="Amazon", paymentProvider="googlePay" — NOT merchant="Google Pay". A bare VPA/phone number with no recognizable business or provider name (e.g. "9876543210@oksbi", "abc123@oksbi") is evidence of nothing beyond itself — do not invent a person's name, a business name, or a merchant type from it; merchant, merchantType, and paymentProvider should all be null/unknown in that case unless something else in the message names them explicitly.
9. Quoting real text from the message is necessary but NOT sufficient — you must also correctly label what KIND of text you're quoting, via merchantEvidenceType/categoryEvidenceType/providerEvidenceType. A VPA string is real, honest evidence that a VPA exists — it is never, by itself, proof of a real-world identity, a category, or a payment provider, no matter how confident you feel about what it "probably" means. Label it 'vpa' and let the app decide how much weight that deserves; do not upgrade your own confidence by mislabeling a VPA quote as 'merchant_name' or a provider-rail quote as evidence for a merchant/category. This labeling is what lets the app tell a strong claim from a weak one even when both technically quote real text.

Always respond by calling the ${CLASSIFY_TOOL_NAME} tool exactly once.`;

export function buildUserMessage(request: ClassifyRequest): string {
  return [
    `Message (already redacted — long digit runs are masked to their last 4): "${request.redactedBody}"`,
    `Sender bank (if recognized): ${request.senderBankName ?? "unknown"}`,
    "This app's own regex reading (for context only — form your own independent judgment):",
    `  amount: ${request.regexEvidence.amount ?? "null"}`,
    `  direction: ${request.regexEvidence.direction ?? "null"}`,
    `  maskedAccount: ${request.regexEvidence.maskedAccount ?? "null"}`,
    `  referenceNumber: ${request.regexEvidence.referenceNumber ?? "null"}`,
    `  merchantGuess: ${request.regexEvidence.merchantGuess ?? "null"}`,
    `  categoryGuess: ${request.regexEvidence.categoryGuess}`,
    `  looksLikeReminder: ${request.regexEvidence.looksLikeReminder}`,
    `  transactionStatus: ${request.regexEvidence.transactionStatus}`,
  ].join("\n");
}
