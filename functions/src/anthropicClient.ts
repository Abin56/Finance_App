import Anthropic from "@anthropic-ai/sdk";
import { ClassifyRequest } from "./types";
import {
  CLASSIFY_TOOL_INPUT_SCHEMA,
  CLASSIFY_TOOL_NAME,
  SYSTEM_PROMPT,
  buildUserMessage,
} from "./prompt";

/**
 * The only file that knows which LLM vendor/model is in use — swapping
 * providers later (OpenAI, Gemini, a different Claude tier) means changing
 * this file alone, mirroring the Flutter side's `FinancialEventAiProvider`
 * seam.
 *
 * Deliberately uses a small/fast model tier: this is single-message
 * structured extraction, not multi-step reasoning, so latency/cost matter
 * more than raw capability here.
 */
const MODEL = "claude-3-5-haiku-latest";

let client: Anthropic | undefined;

function getClient(apiKey: string): Anthropic {
  if (!client) client = new Anthropic({ apiKey });
  return client;
}

/**
 * Calls the model and returns its raw tool-call input, unvalidated — the
 * caller (classifyFinancialSms.ts) runs it through `sanitizeModelOutput`
 * before trusting anything in it. Throws only for a genuine transport-level
 * failure (network, auth, rate limit); a malformed/missing tool call is
 * returned as `undefined` rather than thrown, since that is an expected
 * (if rare) model failure mode, not an exceptional one.
 */
export async function classify(
  apiKey: string,
  request: ClassifyRequest,
): Promise<unknown | undefined> {
  const anthropic = getClient(apiKey);

  const response = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    tools: [
      {
        name: CLASSIFY_TOOL_NAME,
        description: "Report the structured classification of the SMS message.",
        input_schema:
          CLASSIFY_TOOL_INPUT_SCHEMA as unknown as Anthropic.Tool.InputSchema,
      },
    ],
    tool_choice: { type: "tool", name: CLASSIFY_TOOL_NAME },
    messages: [{ role: "user", content: buildUserMessage(request) }],
  });

  const toolUse = response.content.find((block) => block.type === "tool_use");
  if (!toolUse || toolUse.type !== "tool_use") return undefined;
  return toolUse.input;
}
