import '../../../categories/domain/category.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../merchant/merchant_category_suggester.dart';
import '../merchant/merchant_memory.dart';
import '../sms_transaction_category.dart';
import 'merchant_category_resolver_adapter.dart';
import 'merchant_confidence.dart';
import 'merchant_evidence.dart';
import 'merchant_identity.dart';
import 'merchant_identity_cache.dart';
import 'merchant_identity_resolver.dart';
import 'merchant_intelligence_ai_provider.dart';
import 'merchant_type.dart';

/// The combined output this whole module exists to produce: who the
/// counterparty is, what category it implies, and why — see this class's
/// fields for the "MerchantIdentity + MerchantCategory + CategoryConfidence
/// + Evidence" shape this feature was commissioned to deliver.
class MerchantIntelligenceResult {
  const MerchantIntelligenceResult({
    required this.merchant,
    required this.categoryResolution,
  });

  final MerchantIdentity merchant;
  final MerchantCategoryResolution categoryResolution;

  CategorySuggestion? get category => categoryResolution.suggestion;
  MerchantConfidenceLevel get categoryConfidence =>
      categoryResolution.confidenceLevel;
  MerchantEvidence get categoryEvidence => categoryResolution.evidence;
}

/// The single entry point for this module: resolves [MerchantIdentity] and,
/// from it, a category suggestion — composing
/// [MerchantIdentityResolver] and [MerchantAwareCategoryResolver] with an
/// optional AI opinion and an optional cache, without modifying any of the
/// pre-existing `merchant/` or `financial_event/` machinery it builds on.
///
/// # Resolution priority (identity)
/// See [MerchantIdentityResolver]'s class doc for the full deterministic
/// order (VPA parsing -> payment-provider detection -> known catalog ->
/// user history -> individual-name heuristic -> explicit-but-unrecognized
/// text -> unknown). This service adds exactly one more tier *below* all of
/// those: when identity is still [MerchantType.unknown] or
/// [MerchantType.unknownBusiness] and an [aiProvider] is supplied, its
/// opinion may fill in [MerchantIdentity.displayName]/[MerchantType] — but
/// only when nothing deterministic already answered, and the AI's own
/// confidence is always downgraded to [MerchantConfidenceLevel.low]
/// regardless of what it reports (see [MerchantConfidenceX.forEvidence]).
/// An AI opinion is never consulted at all once a known/user-confirmed
/// identity already exists — see "cost/performance" below.
///
/// # Resolution priority (category)
/// See [MerchantAwareCategoryResolver]'s class doc: user history -> the
/// existing narrow seed catalog -> this module's richer catalog -> SMS-body
/// keyword evidence -> AI -> generic SMS-type fallback -> unknown. Same
/// override rule: AI can only fill a gap every earlier tier left empty.
///
/// # Cost/performance
/// [aiProvider] is only invoked when identity resolution comes back
/// unknown/unrecognized AND category resolution also comes back unknown —
/// i.e. never for a known merchant, never for a user-confirmed one, and
/// never when keyword/catalog evidence already answered the category. This
/// is deliberate: known merchants and user history should never cost an AI
/// call (latency, API spend, and the redacted-body privacy exposure that
/// comes with one).
///
/// # Cache
/// When [cache] is supplied, a resolution is looked up by
/// [MerchantIdentity.normalizedName] (or, when that's null, the raw VPA)
/// before doing any work, and the identity half of a fresh result is stored
/// back afterward. Category resolution is intentionally NOT cached (it can
/// legitimately differ per call even for the same merchant — e.g.
/// `transactionType`/`smsCategory` differ, or the user's own category list
/// has changed) — only the merchant *identity* is cached. **Callers that
/// record a user correction via `MerchantMemoryRepository.record` must call
/// `cache.invalidate(normalizedKey)` for the same key immediately
/// afterward** — this service has no way to observe that call itself
/// without modifying `MerchantMemoryRepository` (out of scope for this
/// module).
///
/// # Ambiguous cases (documented, not "fixed")
/// - A bare merchant name whose real-world category genuinely depends on
///   context the message doesn't contain (`Amazon`, `Google`, `Apple`) —
///   [MerchantIdentity.categoryIsAmbiguous] is set `true` and confidence is
///   capped at [MerchantConfidenceLevel.medium] even though the merchant
///   identity itself is fully known; see [MerchantCatalogEntry].
/// - A 2-4-word, business-suffix-free capitalized name — treated as
///   [MerchantType.individual] by heuristic only, never confirmed.
/// - A same-brand alias whose *sub-brand* changes the category (Swiggy vs
///   Swiggy Instamart, Amazon vs Amazon Prime) — resolved correctly only
///   because catalog entries are keyed per sub-brand, not merged.
///
/// # Cases where this service correctly abstains
/// - Any bare VPA/phone-number local part with no catalog match — identity
///   stays unknown; the VPA itself is still surfaced as evidence.
/// - A payment-provider app name mentioned with no real payee (e.g. "via
///   Paytm" alone) — recorded as [MerchantIdentity.paymentProvider], never
///   promoted to merchant identity or a category.
/// - A local/unrecognized business with no keyword evidence in the message
///   (e.g. "XYZ Traders") — category stays unknown; the merchant's explicit
///   name is still kept.
/// - Compound/contextual cases no deterministic rule or keyword covers, and
///   no [aiProvider] is configured — the honest `unknown`/`unknown` result.
class MerchantIntelligenceService {
  MerchantIntelligenceService({
    required MerchantCategorySuggester suggester,
    this.aiProvider,
    this.cache,
    MerchantIdentityResolver? identityResolver,
    MerchantAwareCategoryResolver? categoryResolver,
  }) : _identityResolver = identityResolver ?? const MerchantIdentityResolver(),
       _categoryResolver =
           categoryResolver ?? MerchantAwareCategoryResolver(suggester);

  final MerchantIdentityResolver _identityResolver;
  final MerchantAwareCategoryResolver _categoryResolver;
  final MerchantIntelligenceAiProvider? aiProvider;
  final MerchantIdentityCache? cache;

  Future<MerchantIntelligenceResult> resolve({
    required String? regexMerchantGuess,
    required String smsBody,
    required List<MerchantMemory> memories,
    required TransactionType transactionType,
    required List<Category> categories,
    SmsTransactionCategory? smsCategory,
    String clientRequestId = 'merchant-intel',
  }) async {
    var identity = _identityResolver.resolve(
      regexMerchantGuess: regexMerchantGuess,
      smsBody: smsBody,
      memories: memories,
      transactionType: transactionType,
    );

    final cacheKey = identity.normalizedName ?? identity.vpa?.raw;
    if (cache != null && cacheKey != null) {
      final cached = cache!.get(cacheKey);
      if (cached != null) identity = cached;
    }

    var categoryResolution = _categoryResolver.resolve(
      merchant: identity,
      smsBody: smsBody,
      transactionType: transactionType,
      categories: categories,
      smsCategory: smsCategory,
    );

    final identityNeedsAi =
        !identity.isKnown &&
        identity.merchantType != MerchantType.paymentProvider &&
        (identity.vpa == null || identity.vpa!.localPartIsPhoneNumber == false);
    final categoryNeedsAi = categoryResolution.isUnknown;

    if (aiProvider != null && identityNeedsAi && categoryNeedsAi) {
      final aiResult = await aiProvider!.infer(
        MerchantIntelligenceAiRequest(
          redactedBody: smsBody,
          regexMerchantGuess: regexMerchantGuess,
          vpaLocalPart: identity.vpa?.localPart,
          vpaHandle: identity.vpa?.handle,
          existingCategoryNames: categories.map((c) => c.name).toList(),
          clientRequestId: clientRequestId,
        ),
      );

      if (aiResult != null) {
        // AI can only fill the gap left by deterministic resolution — never
        // override the identity/category already computed above. Since we
        // only reach here when both were unresolved, "filling" and
        // "overriding" coincide, but the guard is kept explicit so future
        // edits can't accidentally let AI run (and win) earlier.
        if (identityNeedsAi &&
            aiResult.merchantName != null &&
            aiResult.merchantName!.trim().isNotEmpty) {
          identity = identity.copyWith(
            displayName: aiResult.merchantName,
            merchantType: MerchantType.unknownBusiness,
            evidence: MerchantEvidence(
              kind: MerchantEvidenceKind.aiInference,
              details: [
                'AI inferred merchant name "${aiResult.merchantName}"'
                    '${aiResult.evidence != null ? ' (${aiResult.evidence})' : ''}',
              ],
            ),
          );
        }

        if (categoryNeedsAi &&
            aiResult.category != null &&
            aiResult.category!.trim().isNotEmpty) {
          categoryResolution = _categoryResolver.resolve(
            merchant: identity,
            smsBody: smsBody,
            transactionType: transactionType,
            categories: categories,
            smsCategory: smsCategory,
            aiCategoryName: aiResult.category,
          );
        }
      }
    }

    if (cache != null && cacheKey != null) {
      cache!.put(cacheKey, identity);
    }

    return MerchantIntelligenceResult(
      merchant: identity,
      categoryResolution: categoryResolution,
    );
  }
}
