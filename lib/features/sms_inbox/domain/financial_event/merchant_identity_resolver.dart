import '../merchant/merchant_key.dart';
import 'ai_claim_validator.dart';
import 'ai_evidence_type.dart';
import 'merchant_catalog.dart';
import 'merchant_identity.dart';
import 'merchant_source.dart';
import 'merchant_type.dart';
import 'payment_provider.dart';
import 'payment_provider_resolver.dart';
import 'vpa_info.dart';

/// Resolves a [MerchantIdentity] — a fuller, explainable read of *who the
/// counterparty is* — from the same regex evidence `FinancialEventExtractor`
/// already has, plus (optionally) an AI opinion. Kept as its own service
/// rather than folded into `MerchantResolver` (which only reconciles the
/// plain display-string `FinancialEvent.merchant` field): this answers a
/// broader question (name, VPA, payment provider, type, catalog evidence)
/// that Phase 1/2 never needed to.
///
/// Split into two methods on purpose:
///  - [resolveDeterministic] never touches AI — it's what `AiCallNecessity`
///    consults to decide whether AI is even worth calling (see that class),
///    and what the pipeline falls back to when AI is unavailable/skipped.
///  - [resolveWithAi] only ever *adds* an AI-sourced identity when the
///    deterministic tiers found nothing (deterministic always outranks AI)
///    and the AI backed its guess with quoted evidence — the same
///    never-invent rule `MerchantResolver` already enforces for the plain
///    merchant field.
///
/// Note on user history: `CategoryResolver`'s existing user-history tier
/// (via `MerchantMemory`) already outranks AI for *category* — that
/// invariant is untouched. This class does not yet have an equivalent
/// "user's preferred display name" store (only a category memory exists
/// today), so [MerchantSource.userHistory] is reserved, not populated, by
/// this phase's [resolveDeterministic].
class MerchantIdentityResolver {
  const MerchantIdentityResolver();

  static final RegExp _genericTokenPattern = RegExp(r'^[xX*\d\s]{4,}$');

  /// VPA/text-catalog resolution only — no AI. Always safe to call, cheap,
  /// and exactly what decides whether AI is necessary at all (see
  /// `AiCallNecessity`).
  MerchantIdentity resolveDeterministic({
    required String? regexMerchantText,
    required String body,
  }) {
    final vpa = regexMerchantText == null
        ? null
        : VpaParser.parse(regexMerchantText);
    final providerResult = PaymentProviderResolver.resolve(
      body: body,
      vpa: vpa,
    );
    final provider = providerResult?.provider;

    if (vpa != null) {
      final catalogEntry = MerchantCatalog.lookupByVpaLocalPart(vpa.localPart);
      if (catalogEntry != null) {
        return MerchantIdentity(
          isKnown: true,
          source: MerchantSource.vpaCatalog,
          confidence: 0.85,
          displayName: catalogEntry.canonicalName,
          normalizedName: MerchantKey.normalize(catalogEntry.canonicalName),
          vpa: vpa,
          paymentProvider: provider,
          merchantType: catalogEntry.merchantType,
          evidence: vpa.raw,
          possibleCategoryNames: catalogEntry.possibleCategoryNames,
        );
      }
      // A bare VPA with no catalog match is evidence, not identity — the
      // single most important case this whole layer exists to get right
      // (see the class-level "never invent merchant identity" principle).
      return MerchantIdentity.unknown(vpa: vpa, paymentProvider: provider);
    }

    if (regexMerchantText != null && regexMerchantText.trim().isNotEmpty) {
      final catalogEntry = MerchantCatalog.lookupByText(regexMerchantText);
      if (catalogEntry != null) {
        return MerchantIdentity(
          isKnown: true,
          source: MerchantSource.merchantCatalog,
          confidence: 0.8,
          displayName: catalogEntry.canonicalName,
          normalizedName: MerchantKey.normalize(catalogEntry.canonicalName),
          paymentProvider: provider,
          merchantType: catalogEntry.merchantType,
          evidence: regexMerchantText.trim(),
          possibleCategoryNames: catalogEntry.possibleCategoryNames,
        );
      }

      // Not in the catalog, but the SMS did name *something* human-shaped
      // (not a bare masked-account/phone/digit token) — a lower-confidence
      // identity backed only by the message's own text, never a guess
      // beyond what's literally there.
      final looksGeneric = _genericTokenPattern.hasMatch(
        regexMerchantText.trim(),
      );
      if (!looksGeneric) {
        return MerchantIdentity(
          isKnown: true,
          source: MerchantSource.explicitText,
          confidence: 0.55,
          displayName: regexMerchantText.trim(),
          normalizedName: MerchantKey.normalize(regexMerchantText),
          paymentProvider: provider,
          evidence: regexMerchantText.trim(),
        );
      }
    }

    return MerchantIdentity.unknown(paymentProvider: provider);
  }

  /// Layers an AI-sourced identity on top of [deterministic] — only when
  /// the deterministic tiers found nothing ([MerchantIdentity.isKnown] is
  /// false), the AI backed its guess with a quoted [aiEvidence] substring,
  /// AND that substring is actually [EvidenceGrounding.isGrounded] in
  /// [body] — a hallucinated quote is treated exactly like no evidence at
  /// all. Deterministic identity always wins outright otherwise; this never
  /// overwrites a catalog/VPA/explicit-text result. [merchantType] is
  /// gated on the same grounded evidence as the merchant name itself (see
  /// this class's doc comment on why the two share one evidence field);
  /// [paymentProvider] is gated implicitly, since this whole method only
  /// runs once merchant grounding has already passed.
  MerchantIdentity resolveWithAi({
    required MerchantIdentity deterministic,
    required String? aiMerchant,
    required String? aiEvidence,
    required double aiConfidence,
    required String? aiMerchantTypeName,
    required String? aiPaymentProviderName,
    required String body,
    List<String>? reasons,
    String? aiEvidenceTypeName,
  }) {
    if (deterministic.isKnown) return deterministic;
    final merchant = aiMerchant?.trim();
    if (merchant == null || merchant.isEmpty) return deterministic;
    if (aiEvidence == null || aiEvidence.trim().isEmpty) return deterministic;
    final verdict = AiClaimValidator.validateMerchant(
      claimedValue: merchant,
      evidence: aiEvidence,
      // See `MerchantResolver.resolve`'s identical rationale: no type at
      // all defaults to the lenient exactText tier for backward
      // compatibility; this is exactly the layer that catches the
      // motivating case a bare grounding check couldn't — a VPA quote
      // "supporting" an invented name.
      evidenceType: aiEvidenceTypeName == null
          ? AiEvidenceType.exactText
          : AiEvidenceTypeX.fromName(aiEvidenceTypeName),
      body: body,
    );
    if (!verdict.accepted) {
      reasons?.add(
        'aiEvidenceNotGrounded: the AI claimed merchant "$merchant" backed '
        'by "$aiEvidence", but ${verdict.rejectionReason} — ignored.',
      );
      return deterministic;
    }

    return MerchantIdentity(
      isKnown: true,
      source: MerchantSource.aiInference,
      confidence: (aiConfidence * 0.85).clamp(0.0, 1.0),
      displayName: merchant,
      normalizedName: MerchantKey.normalize(merchant),
      vpa: deterministic.vpa,
      paymentProvider: aiPaymentProviderName == null
          ? deterministic.paymentProvider
          : PaymentProviderX.fromName(aiPaymentProviderName),
      merchantType: aiMerchantTypeName == null
          ? MerchantType.unknown
          : MerchantTypeX.fromName(aiMerchantTypeName),
      evidence: aiEvidence.trim(),
    );
  }
}
