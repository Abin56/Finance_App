import { sanitizeModelOutput } from "../schema";
import { ALL_NULL_RESPONSE } from "../types";

function validRawOutput(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    eventType: "payment",
    direction: "debit",
    amount: 500,
    merchant: "Swiggy",
    category: "Food & Dining",
    paymentMethod: "upi",
    role: "standalone",
    isLikelyRefundOrReversal: false,
    moneyMovement: true,
    transactionStatus: "success",
    confidence: {
      eventType: 0.9,
      direction: 0.9,
      amount: 0.9,
      merchant: 0.8,
      category: 0.7,
      moneyMovement: 0.9,
      transactionStatus: 0.8,
    },
    evidence: { merchant: "to Swiggy", category: null, eventType: "debited" },
    reasoning: "UPI payment to a food delivery merchant.",
    ...overrides,
  };
}

describe("sanitizeModelOutput", () => {
  it("passes through a well-formed response with matching evidence", () => {
    const result = sanitizeModelOutput(validRawOutput());
    expect(result.merchant).toBe("Swiggy");
    expect(result.eventType).toBe("payment");
    // category has no evidence in the fixture, so it must be stripped even
    // though the model returned a non-null value for it.
    expect(result.category).toBeNull();
  });

  it("strips a merchant value that has no quoted evidence — never invents data", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        evidence: { merchant: null, category: null, eventType: "debited" },
      }),
    );
    expect(result.merchant).toBeNull();
    expect(result.evidence.merchant).toBeNull();
  });

  it("strips a merchant value backed by empty/whitespace-only evidence", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        evidence: { merchant: "   ", category: null, eventType: null },
      }),
    );
    expect(result.merchant).toBeNull();
  });

  it("falls back to ALL_NULL_RESPONSE for malformed input (wrong types)", () => {
    const result = sanitizeModelOutput({
      eventType: 123,
      direction: "sideways",
    });
    expect(result).toEqual(ALL_NULL_RESPONSE);
  });

  it("falls back to ALL_NULL_RESPONSE for completely unrelated input", () => {
    expect(sanitizeModelOutput(null)).toEqual(ALL_NULL_RESPONSE);
    expect(sanitizeModelOutput("not an object")).toEqual(ALL_NULL_RESPONSE);
    expect(sanitizeModelOutput(undefined)).toEqual(ALL_NULL_RESPONSE);
  });

  it("rejects a confidence value outside 0-1 as malformed", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        confidence: {
          eventType: 1.5,
          direction: 0.9,
          amount: 0.9,
          merchant: 0.8,
          category: 0.7,
          moneyMovement: 0.9,
          transactionStatus: 0.8,
        },
      }),
    );
    expect(result).toEqual(ALL_NULL_RESPONSE);
  });

  it("passes through moneyMovement and transactionStatus unchanged (no evidence gate applies to them)", () => {
    const result = sanitizeModelOutput(
      validRawOutput({ moneyMovement: false, transactionStatus: "pending" }),
    );
    expect(result.moneyMovement).toBe(false);
    expect(result.transactionStatus).toBe("pending");
  });

  it("a reminder classification (moneyMovement false) is schema-valid even with a real amount", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        eventType: "reminder",
        moneyMovement: false,
        transactionStatus: "unknown",
        merchant: null,
        evidence: {
          merchant: null,
          category: null,
          eventType: "is due tomorrow",
        },
      }),
    );
    expect(result.moneyMovement).toBe(false);
    expect(result.eventType).toBe("reminder");
    expect(result.amount).toBe(500);
  });

  it("rejects an invalid transactionStatus enum value as malformed", () => {
    const result = sanitizeModelOutput(
      validRawOutput({ transactionStatus: "definitely_not_a_real_status" }),
    );
    expect(result).toEqual(ALL_NULL_RESPONSE);
  });

  it("preserves a genuinely all-null response as-is", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        eventType: null,
        merchant: null,
        category: null,
        evidence: { merchant: null, category: null, eventType: null },
      }),
    );
    expect(result.eventType).toBeNull();
    expect(result.merchant).toBeNull();
  });
});

describe("representative SMS classification shapes", () => {
  // These exercise the schema/sanitization layer with realistic payloads a
  // model might return for varied real-world SMS wording — not a live model
  // call (see the deferred items list for a future mocked-Anthropic
  // end-to-end test), but enough to catch a schema/prompt-contract
  // regression that would break every one of these shapes at once.
  const cases: Array<{ name: string; raw: ReturnType<typeof validRawOutput> }> =
    [
      {
        name: "HDFC debit",
        raw: validRawOutput({ eventType: "payment", direction: "debit" }),
      },
      {
        name: "ICICI credit",
        raw: validRawOutput({
          eventType: "receipt",
          direction: "credit",
          merchant: null,
          evidence: { merchant: null, category: null, eventType: "credited" },
        }),
      },
      {
        name: "UPI refund",
        raw: validRawOutput({
          eventType: "refund",
          isLikelyRefundOrReversal: true,
          evidence: {
            merchant: "from Swiggy",
            category: null,
            eventType: "refunded",
          },
        }),
      },
      {
        name: "credit card bill payment",
        raw: validRawOutput({
          eventType: "creditCardBill",
          role: "linkedSettlement",
          merchant: null,
          evidence: {
            merchant: null,
            category: null,
            eventType: "credit card payment",
          },
        }),
      },
      {
        name: "generic wallet debit, no merchant",
        raw: validRawOutput({
          eventType: "payment",
          merchant: null,
          category: null,
          evidence: {
            merchant: null,
            category: null,
            eventType: "wallet debited",
          },
        }),
      },
      {
        name: "ambiguous/low-info body",
        raw: validRawOutput({
          eventType: null,
          direction: null,
          amount: null,
          merchant: null,
          category: null,
          paymentMethod: null,
          role: null,
          moneyMovement: null,
          transactionStatus: null,
          confidence: {
            eventType: 0,
            direction: 0,
            amount: 0,
            merchant: 0,
            category: 0,
            moneyMovement: 0,
            transactionStatus: 0,
          },
          evidence: { merchant: null, category: null, eventType: null },
        }),
      },
    ];

  for (const { name, raw } of cases) {
    it(`produces schema-conformant output for: ${name}`, () => {
      const result = sanitizeModelOutput(raw);
      expect(result).toHaveProperty("eventType");
      expect(result).toHaveProperty("confidence");
      expect(result).toHaveProperty("evidence");
      // Every non-null merchant/category/eventType must have matching
      // evidence — the core "never invent" invariant, re-checked per case.
      if (result.merchant !== null)
        expect(result.evidence.merchant).toBeTruthy();
      if (result.category !== null)
        expect(result.evidence.category).toBeTruthy();
      if (result.eventType !== null)
        expect(result.evidence.eventType).toBeTruthy();
    });
  }
});

describe("merchantType / paymentProvider — never confuse merchant with provider", () => {
  // A. "Paid Rs.850 to swiggy@upi using PhonePe" — merchant and provider are
  // both known and must stay distinct fields.
  it("resolves a known merchant (business) and a known provider as separate fields", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: "Swiggy",
        category: "Food & Dining",
        merchantType: "business",
        paymentProvider: "phonePe",
        evidence: {
          merchant: "swiggy@upi",
          category: "swiggy@upi",
          eventType: "debited",
        },
      }),
    );
    expect(result.merchant).toBe("Swiggy");
    expect(result.merchantType).toBe("business");
    expect(result.paymentProvider).toBe("phonePe");
    expect(result.merchant).not.toBe(result.paymentProvider);
  });

  // B. "Paid Rs.500 to amazon@upi using Google Pay"
  it("resolves Amazon as the merchant and Google Pay as the provider, never swapped", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: "Amazon",
        category: "Shopping",
        merchantType: "business",
        paymentProvider: "googlePay",
        evidence: {
          merchant: "amazon@upi",
          category: "amazon@upi",
          eventType: "debited",
        },
      }),
    );
    expect(result.merchant).toBe("Amazon");
    expect(result.paymentProvider).toBe("googlePay");
    expect(result.merchant).not.toBe("Google Pay");
  });

  // C. "Rs.500 paid to abc123@oksbi" — a bare, uncatalogued VPA. Unknown is
  // the only honest answer for all three identity-shaped fields.
  it("stays unknown for merchant/merchantType/paymentProvider on a bare uncatalogued VPA", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: null,
        merchantType: null,
        paymentProvider: "unknown",
        evidence: { merchant: null, category: null, eventType: "paid" },
      }),
    );
    expect(result.merchant).toBeNull();
    expect(result.merchantType).toBeNull();
    expect(result.paymentProvider).toBe("unknown");
  });

  // D. "Rs.500 received from Swiggy" — merchant known, no provider phrase
  // anywhere in the message; Swiggy must never leak into paymentProvider.
  it("never lets a known merchant leak into paymentProvider when no provider is named", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        eventType: "receipt",
        direction: "credit",
        merchant: "Swiggy",
        merchantType: "business",
        paymentProvider: null,
        evidence: {
          merchant: "from Swiggy",
          category: null,
          eventType: "credited",
        },
      }),
    );
    expect(result.merchant).toBe("Swiggy");
    expect(result.paymentProvider).not.toBe("Swiggy");
    expect(result.paymentProvider).toBeNull();
  });

  // E. Adversarial: "Rs.500 cashback received through PhonePe" — a provider
  // is named, but no merchant is; PhonePe must never become the merchant.
  it("adversarial: a named provider with no merchant never becomes the merchant", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        eventType: "cashback",
        merchant: null,
        merchantType: null,
        paymentProvider: "phonePe",
        evidence: {
          merchant: null,
          category: null,
          eventType: "cashback received",
        },
      }),
    );
    expect(result.merchant).toBeNull();
    expect(result.paymentProvider).toBe("phonePe");
  });

  // F. Adversarial: "Rs.500 paid using PhonePe" — provider is known from an
  // explicit phrase with no counterparty named at all; paymentProvider does
  // NOT require merchant evidence to survive sanitization.
  it("adversarial: a bare provider-only message resolves the provider without inventing a merchant", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: null,
        merchantType: null,
        paymentProvider: "phonePe",
        evidence: { merchant: null, category: null, eventType: "paid" },
      }),
    );
    expect(result.merchant).toBeNull();
    expect(result.paymentProvider).toBe("phonePe");
  });

  it("strips merchantType when merchant itself has no evidence, even if the model set a value", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: "Some Guess",
        merchantType: "business",
        evidence: { merchant: null, category: null, eventType: "debited" },
      }),
    );
    expect(result.merchant).toBeNull();
    expect(result.merchantType).toBeNull();
  });

  it("rejects an invalid merchantType enum value as malformed", () => {
    const result = sanitizeModelOutput(
      validRawOutput({ merchantType: "food_delivery" }),
    );
    expect(result).toEqual(ALL_NULL_RESPONSE);
  });

  it("rejects an invalid paymentProvider enum value as malformed", () => {
    const result = sanitizeModelOutput(
      validRawOutput({ paymentProvider: "not_a_real_provider" }),
    );
    expect(result).toEqual(ALL_NULL_RESPONSE);
  });

  it("treats a payload predating these fields (absent, not null) as unknown rather than rejecting it", () => {
    const raw = validRawOutput();
    delete (raw as Record<string, unknown>).merchantType;
    delete (raw as Record<string, unknown>).paymentProvider;
    const result = sanitizeModelOutput(raw);
    expect(result.merchantType).toBeNull();
    expect(result.paymentProvider).toBeNull();
  });

  // G. Malicious/unsupported fields (accountNumber, cardNumber, otp, cvv,
  // phoneNumber) must never reach the client — zod strips any key that
  // isn't part of the declared schema, so they're silently dropped rather
  // than surfaced.
  it("silently drops unsupported/malicious fields the model should never return", () => {
    const raw = {
      ...validRawOutput(),
      accountNumber: "1234567890",
      cardNumber: "4111111111111111",
      otp: "998877",
      cvv: "123",
      phoneNumber: "9876543210",
    };
    const result = sanitizeModelOutput(raw) as unknown as Record<
      string,
      unknown
    >;
    expect(result).not.toHaveProperty("accountNumber");
    expect(result).not.toHaveProperty("cardNumber");
    expect(result).not.toHaveProperty("otp");
    expect(result).not.toHaveProperty("cvv");
    expect(result).not.toHaveProperty("phoneNumber");
  });
});

describe("Phase 5 — structured evidence type (a grounded quote is not automatically sufficient)", () => {
  it("THE MOTIVATING CASE: a genuinely grounded VPA quote does not establish an invented merchant", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: "Rahul",
        evidence: {
          merchant: "abc123@oksbi",
          category: null,
          eventType: "debited",
          merchantEvidenceType: "vpa",
        },
      }),
    );
    expect(result.merchant).toBeNull();
    expect(result.merchantType).toBeNull();
  });

  it("an explicit merchant_name evidence type is accepted", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        evidence: {
          merchant: "to Swiggy",
          category: null,
          eventType: "debited",
          merchantEvidenceType: "merchant_name",
        },
      }),
    );
    expect(result.merchant).toBe("Swiggy");
  });

  it("a provider_name evidence type never establishes a merchant claim", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: "PhonePe",
        evidence: {
          merchant: "using PhonePe",
          category: null,
          eventType: "debited",
          merchantEvidenceType: "provider_name",
        },
      }),
    );
    expect(result.merchant).toBeNull();
  });

  it("PAYMENT RAIL ALONE IS INVALID: a provider_name evidence type never establishes a category claim", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        category: "Shopping",
        evidence: {
          merchant: null,
          category: "using PhonePe",
          eventType: "debited",
          categoryEvidenceType: "provider_name",
        },
      }),
    );
    expect(result.category).toBeNull();
  });

  it("a vpa evidence type never establishes a category claim", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        category: "Shopping",
        evidence: {
          merchant: null,
          category: "abc123@oksbi",
          eventType: "debited",
          categoryEvidenceType: "vpa",
        },
      }),
    );
    expect(result.category).toBeNull();
  });

  it("a contextual_phrase evidence type is accepted for category", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        category: "Food & Dining",
        evidence: {
          merchant: null,
          category: "a restaurant order",
          eventType: "debited",
          categoryEvidenceType: "contextual_phrase",
        },
      }),
    );
    expect(result.category).toBe("Food & Dining");
  });

  it("paymentProvider requires an explicit provider_name evidence type once one is specified", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: null,
        paymentProvider: "phonePe",
        evidence: {
          merchant: null,
          category: null,
          eventType: "debited",
          providerEvidenceType: "vpa",
        },
      }),
    );
    expect(result.paymentProvider).toBeNull();
  });

  it("paymentProvider is accepted when providerEvidenceType is explicitly provider_name", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: null,
        paymentProvider: "phonePe",
        evidence: {
          merchant: null,
          category: null,
          eventType: "debited",
          providerEvidenceType: "provider_name",
        },
      }),
    );
    expect(result.paymentProvider).toBe("phonePe");
  });

  it("paymentProvider is accepted when no evidence type is specified at all (backward compatibility)", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        merchant: null,
        paymentProvider: "phonePe",
        evidence: { merchant: null, category: null, eventType: "debited" },
      }),
    );
    expect(result.paymentProvider).toBe("phonePe");
  });

  it("rejects an invalid evidence-type enum value as malformed", () => {
    const result = sanitizeModelOutput(
      validRawOutput({
        evidence: {
          merchant: "to Swiggy",
          category: null,
          eventType: "debited",
          merchantEvidenceType: "not_a_real_type",
        },
      }),
    );
    expect(result).toEqual(ALL_NULL_RESPONSE);
  });
});
