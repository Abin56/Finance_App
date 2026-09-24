import 'merchant_source.dart';
import 'merchant_type.dart';
import 'payment_provider.dart';
import 'vpa_info.dart';

/// A fully-explained read of *who the counterparty is* — richer than the
/// plain `FieldConfidence<String> merchant` field `FinancialEvent` already
/// carries (which only holds a display string). Produced by
/// [MerchantIdentityResolver] as an intermediate, explainable result; its
/// [displayName] and evidence feed into that existing `merchant` field
/// rather than replacing it, and its [paymentProvider]/[merchantType] feed
/// two small new `FinancialEvent` fields — see that class's doc comment for
/// why this stays an adapter layer rather than a `FinancialEvent` schema
/// rewrite.
///
/// [isKnown] is the honest headline: `false` is a completely normal, valid
/// result (see this feature's "never invent merchant identity" principle) —
/// a bare VPA, a phone number, or a masked account number is evidence, not
/// identity, and must never be inflated into a guessed name.
class MerchantIdentity {
  const MerchantIdentity({
    required this.isKnown,
    required this.source,
    required this.confidence,
    this.displayName,
    this.normalizedName,
    this.vpa,
    this.paymentProvider,
    this.merchantType = MerchantType.unknown,
    this.evidence,
    this.possibleCategoryNames = const [],
  });

  /// The canonical "we don't know" result — every field left honestly
  /// empty/unknown rather than guessed.
  const MerchantIdentity.unknown({this.vpa, this.paymentProvider})
    : isKnown = false,
      source = MerchantSource.unknown,
      confidence = 0.0,
      displayName = null,
      normalizedName = null,
      merchantType = MerchantType.unknown,
      evidence = null,
      possibleCategoryNames = const [];

  /// `false` is a completely valid, common outcome — see class doc.
  final bool isKnown;

  final MerchantSource source;

  /// 0.0-1.0 — how confident this specific identity resolution is, entirely
  /// independent of `FinancialEvent.overallConfidence`.
  final double confidence;

  /// The human-shown name, e.g. `"Swiggy"` — only set when [isKnown].
  final String? displayName;

  /// `MerchantKey.normalize(displayName)` — the lookup key other parts of
  /// this feature (merchant memory, category suggestions) already use.
  final String? normalizedName;

  /// The parsed VPA, when the message contained one — kept even when
  /// [isKnown] is false, since a bare VPA is exactly the kind of evidence
  /// this class exists to preserve rather than discard.
  final VpaInfo? vpa;

  /// The rail/app that moved the money — see [PaymentProvider]'s doc for
  /// why this is never conflated with the merchant.
  final PaymentProvider? paymentProvider;

  final MerchantType merchantType;

  /// Human-readable justification, shown verbatim to a reviewer — same
  /// transparency principle every other resolver/matcher in this feature
  /// already follows.
  final String? evidence;

  /// Informational category hints from [MerchantCatalog] — never used to
  /// bypass the real `CategoryResolver`, only as debug/explanatory context.
  final List<String> possibleCategoryNames;
}
