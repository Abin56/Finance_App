import 'merchant_evidence.dart';
import 'merchant_type.dart';
import 'upi_provider.dart';
import 'vpa_info.dart';

/// Who/what a transaction's counterparty is — deliberately independent of
/// *category* (see `MerchantCatalogEntry`'s doc comment and
/// `MerchantAwareCategoryResolver`): this model answers "who," a separate
/// resolver answers "what for."
///
/// Every field is populated only from evidence FlowFi actually observed —
/// see the class-level "no hallucination" rule this whole module is built
/// around. [displayName] is never invented beyond either (a) a
/// [MerchantIntelligenceCatalog] entry's own name, (b) explicit merchant text
/// the message itself contained verbatim, or (c) the user's own prior
/// choice — never guessed from a VPA's local part or a phone number.
class MerchantIdentity {
  const MerchantIdentity({
    this.displayName,
    this.normalizedName,
    this.vpa,
    this.paymentProvider,
    required this.merchantType,
    required this.isKnown,
    this.isUserConfirmed = false,
    this.categoryIsAmbiguous = false,
    required this.evidence,
  });

  /// The single, honest "we don't know anything" identity — used whenever
  /// there's no merchant-shaped text, no VPA, and no other signal at all.
  const MerchantIdentity.unknown()
    : displayName = null,
      normalizedName = null,
      vpa = null,
      paymentProvider = null,
      merchantType = MerchantType.unknown,
      isKnown = false,
      isUserConfirmed = false,
      categoryIsAmbiguous = false,
      evidence = const MerchantEvidence.none();

  /// Human-readable name — a catalog display name, the raw extracted text
  /// (e.g. `'ABC Bakery'`), or `null` when nothing at all was extractable.
  /// Deliberately never a VPA or phone number dressed up as a name; see
  /// [vpa] for that evidence instead.
  final String? displayName;

  /// `MerchantKey.normalize`'d form of [displayName] (or of the raw VPA
  /// local part when that's all there was) — the same key
  /// `MerchantMemory`/`MerchantCategorySuggester` key their history against,
  /// so this model composes with the existing user-learning machinery
  /// without needing its own parallel key space.
  final String? normalizedName;

  /// Present whenever the message evidence included a UPI VPA — kept
  /// regardless of whether [displayName] resolved, since the VPA is itself
  /// useful evidence a reviewing user can recognize even when FlowFi
  /// couldn't name the business.
  final VpaInfo? vpa;

  /// The payment app/rail used (PhonePe, Google Pay, Paytm, ...), if
  /// mentioned — always kept separate from [displayName]/[merchantType],
  /// per this module's "payment provider is not the merchant" rule.
  final UpiProvider? paymentProvider;

  final MerchantType merchantType;

  /// True once this exact merchant is recognized — either via
  /// [MerchantIntelligenceCatalog] or the user's own transaction history
  /// (see [isUserConfirmed]). False for [MerchantType.unknownBusiness],
  /// [MerchantType.individual] (heuristic, not a catalog match), and
  /// [MerchantType.unknown].
  final bool isKnown;

  /// True when the user has personally transacted with (and categorized)
  /// this normalized merchant before — the strongest form of "known," since
  /// it reflects the user's own real history rather than a static catalog
  /// FlowFi shipped with. See [MerchantAwareCategoryResolver] for how this
  /// outranks both the catalog and AI on the category side.
  final bool isUserConfirmed;

  /// Mirrors `MerchantCatalogEntry.categoryIsAmbiguous` for whichever
  /// catalog entry (if any) backed this identity — surfaced here so a
  /// caller can cap confidence appropriately even when only asking about
  /// identity, not category.
  final bool categoryIsAmbiguous;

  final MerchantEvidence evidence;

  MerchantIdentity copyWith({
    String? displayName,
    String? normalizedName,
    VpaInfo? vpa,
    UpiProvider? paymentProvider,
    MerchantType? merchantType,
    bool? isKnown,
    bool? isUserConfirmed,
    bool? categoryIsAmbiguous,
    MerchantEvidence? evidence,
  }) {
    return MerchantIdentity(
      displayName: displayName ?? this.displayName,
      normalizedName: normalizedName ?? this.normalizedName,
      vpa: vpa ?? this.vpa,
      paymentProvider: paymentProvider ?? this.paymentProvider,
      merchantType: merchantType ?? this.merchantType,
      isKnown: isKnown ?? this.isKnown,
      isUserConfirmed: isUserConfirmed ?? this.isUserConfirmed,
      categoryIsAmbiguous: categoryIsAmbiguous ?? this.categoryIsAmbiguous,
      evidence: evidence ?? this.evidence,
    );
  }

  @override
  String toString() =>
      'MerchantIdentity(displayName: $displayName, type: ${merchantType.name}, '
      'isKnown: $isKnown, isUserConfirmed: $isUserConfirmed, vpa: $vpa, '
      'paymentProvider: ${paymentProvider?.label}, evidence: $evidence)';
}
