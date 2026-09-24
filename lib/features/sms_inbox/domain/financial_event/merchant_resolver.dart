import 'dart:math' as math;

import '../merchant/merchant_key.dart';
import 'ai_claim_validator.dart';
import 'ai_evidence_type.dart';
import 'field_confidence.dart';

/// Reconciles the regex-extracted merchant/counterparty guess with the AI's
/// independent read into one [FieldConfidence]. Named and tested on its own
/// (previously inline in `FinancialEventExtractor`) so merchant-resolution
/// behavior — the single field most prone to "plausible-sounding but wrong"
/// AI output — can be reasoned about and improved in isolation.
///
/// The same class also resolves a **person's name** in a P2P transfer (e.g.
/// "trf to RAHUL KUMAR") — this feature has no separate sender/receiver-name
/// field; a counterparty name is a counterparty name whether it belongs to a
/// business or a person, so the same evidence-required, never-invent rule
/// applies uniformly rather than needing a second, parallel resolver.
///
/// Rules:
/// - Only one signal has a value → use it.
/// - Both agree (same normalized key) → boosted confidence.
/// - AI has a value but no quoted evidence backing it → treated exactly like
///   "AI had no opinion," never trusted (see the SMS AI rebuild plan's
///   "never invent merchant/category/people" requirement).
/// - Both disagree → the AI wins only when the regex guess is a bare UPI VPA
///   or a bare masked-account/phone-shaped token (nothing a human would
///   recognize as a name) — a confident, human-shaped regex value is never
///   silently overridden by an unverifiable AI opinion. Either way, the
///   conflict is always recorded, never silently resolved.
abstract class MerchantResolver {
  MerchantResolver._();

  static const double _aiOnlyDiscount = 0.85;
  static const double _agreementBonus = 0.15;
  static const double _disagreementCap = 0.4;

  /// A bare UPI VPA (`someone@bank`) or a purely numeric/masked token
  /// (`XXXX1234`, a phone number) carries no human-readable identity — the
  /// AI's semantic read is trusted to improve on it, but a real name is not.
  static final RegExp _genericRegexPattern = RegExp(
    r'^([\w.\-]{2,}@[a-zA-Z]{2,}|[xX*\d\s]{4,})$',
  );

  static FieldConfidence<String> resolve({
    required String? regexMerchant,
    required String? aiMerchant,
    required String? aiEvidence,
    required double aiConfidence,
    required List<String> reasons,
    required String body,
    String? aiEvidenceTypeName,
  }) {
    final regexValue = regexMerchant?.trim();
    final aiValue = aiMerchant?.trim();

    if ((aiValue == null || aiValue.isEmpty) &&
        (regexValue == null || regexValue.isEmpty)) {
      return const FieldConfidence<String>.unknown();
    }
    if (aiValue == null || aiValue.isEmpty) {
      return FieldConfidence<String>(
        value: regexValue,
        confidence: 0.6,
        source: EvidenceSource.regexOnly,
        regexEvidence: regexValue,
      );
    }
    // The AI must back a merchant/person guess with a quoted substring that
    // genuinely occurs in the message — an unevidenced AI value, or one
    // whose "evidence" cannot be found in the actual SMS (a hallucinated
    // quote), is treated exactly like "AI had no opinion," never trusted,
    // per the "never invent data" principle. A grounding failure is
    // recorded, not silently dropped — a human reviewer should know the AI
    // tried to claim something the message doesn't support.
    if (aiEvidence == null || aiEvidence.trim().isEmpty) {
      return regexValue == null || regexValue.isEmpty
          ? const FieldConfidence<String>.unknown()
          : FieldConfidence<String>(
              value: regexValue,
              confidence: 0.6,
              source: EvidenceSource.regexOnly,
              regexEvidence: regexValue,
            );
    }
    final verdict = AiClaimValidator.validateMerchant(
      claimedValue: aiValue,
      evidence: aiEvidence,
      // No type specified at all (as opposed to an explicit, unrecognized
      // one) defaults to the lenient exactText tier — a plain grounded
      // quote, exactly Phase 4's behavior — so a provider that doesn't yet
      // populate this new field is neither newly broken nor newly trusted
      // beyond what it already was.
      evidenceType: aiEvidenceTypeName == null
          ? AiEvidenceType.exactText
          : AiEvidenceTypeX.fromName(aiEvidenceTypeName),
      body: body,
    );
    if (!verdict.accepted) {
      reasons.add(
        'aiEvidenceNotGrounded: the AI claimed merchant "$aiValue" backed by '
        '"$aiEvidence", but ${verdict.rejectionReason} — ignored.',
      );
      return regexValue == null || regexValue.isEmpty
          ? const FieldConfidence<String>.unknown()
          : FieldConfidence<String>(
              value: regexValue,
              confidence: 0.6,
              source: EvidenceSource.regexOnly,
              regexEvidence: regexValue,
            );
    }
    if (regexValue == null || regexValue.isEmpty) {
      return FieldConfidence<String>(
        value: aiValue,
        confidence: (aiConfidence * _aiOnlyDiscount).clamp(0.0, 1.0),
        source: EvidenceSource.aiOnly,
        aiEvidence: aiEvidence,
      );
    }

    final sameKey =
        MerchantKey.normalize(regexValue) == MerchantKey.normalize(aiValue);
    if (sameKey) {
      return FieldConfidence<String>(
        value: aiValue.length >= regexValue.length ? aiValue : regexValue,
        confidence: (math.max(0.6, aiConfidence) + _agreementBonus).clamp(
          0.0,
          1.0,
        ),
        source: EvidenceSource.bothAgree,
        regexEvidence: regexValue,
        aiEvidence: aiEvidence,
      );
    }

    final regexLooksGeneric = _genericRegexPattern.hasMatch(regexValue);
    reasons.add(
      'Regex read the merchant as "$regexValue" but AI read "$aiValue" — please confirm.',
    );
    if (regexLooksGeneric) {
      return FieldConfidence<String>(
        value: aiValue,
        confidence: _disagreementCap,
        source: EvidenceSource.bothDisagree,
        regexEvidence: regexValue,
        aiEvidence: aiEvidence,
      );
    }
    return FieldConfidence<String>(
      value: regexValue,
      confidence: _disagreementCap,
      source: EvidenceSource.bothDisagree,
      regexEvidence: regexValue,
      aiEvidence: aiEvidence,
    );
  }
}
