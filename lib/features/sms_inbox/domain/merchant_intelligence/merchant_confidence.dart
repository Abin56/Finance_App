import 'merchant_evidence.dart';

/// A coarse, human-meaningful confidence tier for a merchant-intelligence
/// decision — deliberately not a bare float. Every tier below is derived
/// from *what kind of evidence* backed the decision (see
/// [MerchantConfidenceX.forEvidence]), never assigned as an arbitrary
/// hardcoded number picked without regard to evidence quality.
enum MerchantConfidenceLevel {
  /// Strong merchant identity (user-confirmed or catalog-matched) feeding a
  /// resolved, non-ambiguous category.
  high,

  /// The merchant itself is known/confirmed, but the category is ambiguous
  /// or only loosely implied (e.g. Amazon's category depends on context the
  /// merchant name alone doesn't settle).
  medium,

  /// The only evidence is an AI inference with nothing else corroborating
  /// it.
  low,

  /// Not enough evidence to say anything at all — the correct, honest answer
  /// far more often than users might expect, and never treated as a
  /// failure state to paper over.
  unknown,
}

extension MerchantConfidenceX on MerchantConfidenceLevel {
  String get label {
    switch (this) {
      case MerchantConfidenceLevel.high:
        return 'High';
      case MerchantConfidenceLevel.medium:
        return 'Medium';
      case MerchantConfidenceLevel.low:
        return 'Low';
      case MerchantConfidenceLevel.unknown:
        return 'Unknown';
    }
  }

  /// Derives a confidence tier purely from the *kind* of evidence backing a
  /// decision — see each enum value's doc comment for the reasoning encoded
  /// here. [merchantIsAmbiguousCategory] should be set when a known merchant
  /// legitimately maps to more than one plausible category (e.g. Amazon)
  /// and the category itself wasn't independently resolved (no user
  /// history, no specific catalog subcategory hit) — this caps an otherwise
  /// "high" merchant match down to "medium" for the *category* half of the
  /// result, without discounting the merchant identity itself.
  static MerchantConfidenceLevel forEvidence(
    MerchantEvidenceKind kind, {
    bool merchantIsAmbiguousCategory = false,
  }) {
    switch (kind) {
      case MerchantEvidenceKind.userConfirmed:
      case MerchantEvidenceKind.knownMerchantCatalog:
        return merchantIsAmbiguousCategory
            ? MerchantConfidenceLevel.medium
            : MerchantConfidenceLevel.high;
      case MerchantEvidenceKind.keywordMatch:
      case MerchantEvidenceKind.regex:
        return MerchantConfidenceLevel.medium;
      case MerchantEvidenceKind.aiInference:
        return MerchantConfidenceLevel.low;
      case MerchantEvidenceKind.none:
        return MerchantConfidenceLevel.unknown;
    }
  }
}
