import 'ai_evidence_type.dart';
import 'evidence_grounding.dart';

/// The outcome of validating one AI claim — never just a bool, so a
/// rejection always carries a human-readable reason a reviewer (or a test
/// assertion) can act on, the same transparency principle every other
/// resolver/matcher in this feature already follows.
class AiClaimVerdict {
  const AiClaimVerdict.accept() : accepted = true, rejectionReason = null;

  const AiClaimVerdict.reject(String reason)
    : accepted = false,
      rejectionReason = reason;

  final bool accepted;
  final String? rejectionReason;
}

/// Implements the validation pipeline this phase's spec lays out:
///
/// ```
/// AI CLAIM
///   -> evidence exists?
///   -> evidence is in the SMS? (EvidenceGrounding)
///   -> evidence type is valid?
///   -> evidence type actually supports the requested field?
///   -> accept / reject
/// ```
///
/// Grounding alone (`EvidenceGrounding`) only answers "is this real text
/// from the message" — it cannot tell a VPA quote from a merchant-name
/// quote, so a grounded-but-irrelevant quote (a real VPA "supporting" an
/// invented person's name) passed Phase 4's check. This class adds the
/// missing step: *which kind* of text is being quoted, and whether that
/// kind is strong enough for the specific claim it's backing.
///
/// Each field has its own rule, matching this phase's spec:
///  - **merchant**: [AiEvidenceType.merchantName]/[AiEvidenceType.exactText]
///    are strong; [AiEvidenceType.vpa] alone is never enough (a VPA is
///    evidence of the VPA, not a verified identity — the deterministic
///    catalog tiers already handle the cases where a VPA genuinely does
///    resolve to a known business); [AiEvidenceType.providerName] is
///    rejected outright (a provider is never a merchant).
///  - **merchantType**: mirrors merchant's rule — the same evidence that
///    justifies *who* the counterparty is must also justify *what kind* of
///    counterparty it is.
///  - **category**: [AiEvidenceType.merchantName]/[AiEvidenceType.exactText]/
///    [AiEvidenceType.contextualPhrase] are accepted; anything that reduces
///    to "this used payment rail X" is not a category signal at all (that
///    invariant is already enforced structurally — the AI is never even
///    asked to justify a category from a payment-method word — so this
///    validator's category rule mainly guards against a
///    [AiEvidenceType.providerName]/[AiEvidenceType.amount]/
///    [AiEvidenceType.account] quote being misused as category evidence).
///  - **paymentProvider**: [AiEvidenceType.providerName] is strong;
///    everything else is rejected — a VPA handle alone is a deterministic
///    *hint*, not something the AI gets to assert outright (see
///    `PaymentProviderResolver` for that existing, separate weak-hint
///    tier).
abstract class AiClaimValidator {
  AiClaimValidator._();

  static AiClaimVerdict validateMerchant({
    required String? claimedValue,
    required String? evidence,
    required AiEvidenceType evidenceType,
    required String body,
  }) => _validateIdentityLikeField(
    fieldLabel: 'merchant',
    claimedValue: claimedValue,
    evidence: evidence,
    evidenceType: evidenceType,
    body: body,
  );

  static AiClaimVerdict validateMerchantType({
    required String? claimedValue,
    required String? evidence,
    required AiEvidenceType evidenceType,
    required String body,
  }) => _validateIdentityLikeField(
    fieldLabel: 'merchantType',
    claimedValue: claimedValue,
    evidence: evidence,
    evidenceType: evidenceType,
    body: body,
  );

  static AiClaimVerdict _validateIdentityLikeField({
    required String fieldLabel,
    required String? claimedValue,
    required String? evidence,
    required AiEvidenceType evidenceType,
    required String body,
  }) {
    if (claimedValue == null || claimedValue.trim().isEmpty) {
      return const AiClaimVerdict.reject('no claim made');
    }
    if (evidence == null || evidence.trim().isEmpty) {
      return AiClaimVerdict.reject('$fieldLabel: no evidence supplied');
    }
    if (!EvidenceGrounding.isGrounded(evidence: evidence, body: body)) {
      return AiClaimVerdict.reject(
        '$fieldLabel: evidence "$evidence" does not occur in the message',
      );
    }
    switch (evidenceType) {
      case AiEvidenceType.merchantName:
      case AiEvidenceType.exactText:
        return const AiClaimVerdict.accept();
      case AiEvidenceType.vpa:
        return AiClaimVerdict.reject(
          '$fieldLabel: a VPA is evidence of the VPA string, not a verified '
          'identity — a bare, uncatalogued VPA can never establish who it '
          'belongs to',
        );
      case AiEvidenceType.providerName:
        return AiClaimVerdict.reject(
          '$fieldLabel: this evidence names a payment provider, not a '
          'merchant — a provider is never the merchant',
        );
      case AiEvidenceType.transactionKeyword:
      case AiEvidenceType.amount:
      case AiEvidenceType.account:
        return AiClaimVerdict.reject(
          '$fieldLabel: this evidence type cannot support an identity claim',
        );
      case AiEvidenceType.contextualPhrase:
        // A descriptive phrase can corroborate an identity claim
        // (e.g. "at the corner store") but is weaker than a name being
        // stated directly — accepted, but callers may still discount its
        // confidence relative to exactText/merchantName (see
        // `FinancialEventExtractor`).
        return const AiClaimVerdict.accept();
      case AiEvidenceType.unknown:
        return AiClaimVerdict.reject(
          '$fieldLabel: evidence type unspecified/unrecognized — treated as '
          'the weakest tier, not enough on its own for an identity claim',
        );
    }
  }

  static AiClaimVerdict validateCategory({
    required String? claimedValue,
    required String? evidence,
    required AiEvidenceType evidenceType,
    required String body,
  }) {
    if (claimedValue == null || claimedValue.trim().isEmpty) {
      return const AiClaimVerdict.reject('no claim made');
    }
    if (evidence == null || evidence.trim().isEmpty) {
      return const AiClaimVerdict.reject('category: no evidence supplied');
    }
    if (!EvidenceGrounding.isGrounded(evidence: evidence, body: body)) {
      return AiClaimVerdict.reject(
        'category: evidence "$evidence" does not occur in the message',
      );
    }
    switch (evidenceType) {
      case AiEvidenceType.merchantName:
      case AiEvidenceType.exactText:
      case AiEvidenceType.contextualPhrase:
        return const AiClaimVerdict.accept();
      case AiEvidenceType.providerName:
        return const AiClaimVerdict.reject(
          'category: a payment provider/rail is not a spending category',
        );
      case AiEvidenceType.vpa:
      case AiEvidenceType.transactionKeyword:
      case AiEvidenceType.amount:
      case AiEvidenceType.account:
        return const AiClaimVerdict.reject(
          'category: this evidence type cannot support a category claim',
        );
      case AiEvidenceType.unknown:
        return const AiClaimVerdict.reject(
          'category: evidence type unspecified/unrecognized',
        );
    }
  }

  static AiClaimVerdict validatePaymentProvider({
    required String? claimedValue,
    required String? evidence,
    required AiEvidenceType evidenceType,
    required String body,
  }) {
    if (claimedValue == null || claimedValue.trim().isEmpty) {
      return const AiClaimVerdict.reject('no claim made');
    }
    if (evidence == null || evidence.trim().isEmpty) {
      return const AiClaimVerdict.reject(
        'paymentProvider: no evidence supplied',
      );
    }
    if (!EvidenceGrounding.isGrounded(evidence: evidence, body: body)) {
      return AiClaimVerdict.reject(
        'paymentProvider: evidence "$evidence" does not occur in the message',
      );
    }
    if (evidenceType == AiEvidenceType.providerName) {
      return const AiClaimVerdict.accept();
    }
    return AiClaimVerdict.reject(
      'paymentProvider: only an explicit provider-name phrase can establish '
      'the payment provider (evidenceType was ${evidenceType.name})',
    );
  }
}
