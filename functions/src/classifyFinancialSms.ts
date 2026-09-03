import { HttpsError, onCall } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import { classify } from "./anthropicClient";
import { ClassifyRequestSchema, sanitizeModelOutput } from "./schema";
import { ALL_NULL_RESPONSE } from "./types";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

/**
 * Classifies one already-locally-filtered SMS into a structured
 * `FinancialEvent` reading — see the Flutter side's
 * `CloudFunctionFinancialEventAiProvider`. Requires an authenticated caller
 * (Firebase Auth), same posture as every Firestore rule in this app
 * (`isOwner(uid)`); an anonymous call is rejected outright rather than
 * silently classified.
 *
 * On any LLM-side failure (timeout, malformed output, rate limit) this
 * returns {@link ALL_NULL_RESPONSE} rather than throwing, so the client's
 * `CloudFunctionFinancialEventAiProvider.classify` only ever needs to
 * distinguish "function unreachable" (a real error) from "AI had nothing to
 * say" (a well-formed, all-null response) — never a third malformed-JSON
 * case.
 *
 * Deliberately logs only the error shape and `clientRequestId` — never
 * `redactedBody`/`regexEvidence` — so a failure never leaks SMS content
 * into function logs, even though the body reaching this function is
 * already redacted client-side.
 */
export const classifyFinancialSms = onCall(
  { secrets: [anthropicApiKey], timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const parsed = ClassifyRequestSchema.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Malformed classify request.");
    }

    try {
      const rawOutput = await classify(anthropicApiKey.value(), parsed.data);
      if (rawOutput === undefined) {
        logger.warn("classifyFinancialSms: model returned no tool call", {
          clientRequestId: parsed.data.clientRequestId,
        });
        return ALL_NULL_RESPONSE;
      }
      return sanitizeModelOutput(rawOutput);
    } catch (error) {
      logger.error(
        "classifyFinancialSms: LLM call failed, returning fallback",
        {
          clientRequestId: parsed.data.clientRequestId,
          error: error instanceof Error ? error.message : String(error),
        },
      );
      return ALL_NULL_RESPONSE;
    }
  },
);
