/// Everything a merchant/category AI inference call is given — deliberately
/// the same redacted, minimal shape as `FinancialEventAiRequest`: never the
/// user's account list, never anything beyond what's needed to guess a
/// merchant/category. [smsBody] must already be redacted the same way
/// `SmsBodyRedactor` redacts it for the main financial-event AI call before
/// being placed here — this class doesn't redact anything itself.
class MerchantIntelligenceAiRequest {
  const MerchantIntelligenceAiRequest({
    required this.redactedBody,
    required this.regexMerchantGuess,
    required this.vpaLocalPart,
    required this.vpaHandle,
    required this.existingCategoryNames,
    required this.clientRequestId,
  });

  final String redactedBody;

  /// Whatever the deterministic layer already extracted, if anything — the
  /// AI is asked to refine/confirm this, never to contradict a
  /// [MerchantIntelligenceAiRequest] caller's already-strong evidence (that
  /// contract lives in [MerchantIdentityResolver]/`MerchantAwareCategoryResolver`,
  /// not here — this class is just the wire format).
  final String? regexMerchantGuess;

  /// Never a full VPA (which pairs a business/person slug with a bank
  /// handle) — only the parts already split out, so the AI can reason about
  /// "does `swiggy` look like a food business" without ever being handed
  /// something that reads as a phone number to itself invent a person from.
  final String? vpaLocalPart;
  final String? vpaHandle;

  /// The user's real category names (not full `Category` objects — no ids,
  /// no colors/icons) — so the AI can answer using a name that actually
  /// exists rather than inventing a new taxonomy the app doesn't have.
  final List<String> existingCategoryNames;

  final String clientRequestId;

  Map<String, dynamic> toJson() => {
    'redactedBody': redactedBody,
    'regexMerchantGuess': regexMerchantGuess,
    'vpaLocalPart': vpaLocalPart,
    'vpaHandle': vpaHandle,
    'existingCategoryNames': existingCategoryNames,
    'clientRequestId': clientRequestId,
  };
}

/// An AI's opinion on merchant identity and category — every field optional,
/// `null`/`isUnknown` being the *correct* answer whenever the model has
/// insufficient evidence. The system prompt behind any real implementation
/// of [MerchantIntelligenceAiProvider] MUST instruct the model, explicitly:
///
/// - Never invent a merchant name, a person's name, a category, an amount, a
///   reference id, a VPA, or an account number that isn't directly supported
///   by [MerchantIntelligenceAiRequest.redactedBody] or its other fields.
/// - A bare phone number or opaque VPA local part is NOT evidence of a
///   person's identity — return `merchantName: null` rather than guess one.
/// - When evidence is insufficient, return every field `null` (or use
///   [MerchantIntelligenceAiResult.unknown]) rather than a low-confidence
///   guess dressed up as a normal answer.
///
/// This is documentation, not enforcement — enforcement is
/// [MerchantIdentityResolver]/`MerchantAwareCategoryResolver` never letting
/// an AI result override strong deterministic or user-confirmed evidence,
/// regardless of what the model claims.
class MerchantIntelligenceAiResult {
  const MerchantIntelligenceAiResult({
    this.merchantName,
    this.merchantType,
    this.category,
    this.subcategory,
    this.confidence = 0.0,
    this.evidence,
  });

  const MerchantIntelligenceAiResult.unknown()
    : merchantName = null,
      merchantType = null,
      category = null,
      subcategory = null,
      confidence = 0.0,
      evidence = null;

  final String? merchantName;

  /// The raw `MerchantType.name` string the model chose, if any — parsed by
  /// the caller so an unrecognized value degrades to `null` rather than
  /// throwing.
  final String? merchantType;
  final String? category;
  final String? subcategory;

  /// 0.0-1.0, the model's own stated confidence — always discounted further
  /// by the caller before use, per [MerchantEvidenceKind.aiInference] always
  /// grading out at [MerchantConfidenceLevel.low] regardless of what value
  /// is reported here.
  final double confidence;

  /// The model's own cited reasoning/quoted evidence — surfaced verbatim in
  /// [MerchantEvidence.details] so a reviewer can see exactly what the model
  /// based its answer on.
  final String? evidence;

  factory MerchantIntelligenceAiResult.fromJson(Map<String, dynamic> json) {
    return MerchantIntelligenceAiResult(
      merchantName: json['merchantName'] as String?,
      merchantType: json['merchantType'] as String?,
      category: json['category'] as String?,
      subcategory: json['subcategory'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      evidence: json['evidence'] as String?,
    );
  }
}

/// Adapter interface for an (optional) AI opinion on merchant identity and
/// category — mirrors `FinancialEventAiProvider`'s contract exactly:
/// implementations must **never throw**; any failure (timeout, malformed
/// response, no network) returns `null`, treated identically to "AI
/// abstained." No concrete (Cloud Function-backed) implementation is
/// provided by this module — wiring a real backend is a separate,
/// deliberately deferred step (see this module's parallel-development
/// notes); [NoopMerchantIntelligenceAiProvider] is the safe default, and
/// tests use a small fake implementing this interface directly, matching
/// this codebase's existing convention (see `_FakeAiProvider` in
/// `financial_event_extractor_test.dart`) rather than a mocking library.
abstract class MerchantIntelligenceAiProvider {
  Future<MerchantIntelligenceAiResult?> infer(
    MerchantIntelligenceAiRequest request,
  );
}

class NoopMerchantIntelligenceAiProvider
    implements MerchantIntelligenceAiProvider {
  const NoopMerchantIntelligenceAiProvider();

  @override
  Future<MerchantIntelligenceAiResult?> infer(
    MerchantIntelligenceAiRequest request,
  ) async => null;
}
