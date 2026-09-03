import '../../../categories/domain/category.dart';
import '../../../categories/domain/category_type.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../merchant/merchant_category_suggester.dart';
import '../sms_transaction_category.dart';
import 'category_keyword_matcher.dart';
import 'merchant_catalog.dart';
import 'merchant_confidence.dart';
import 'merchant_evidence.dart';
import 'merchant_identity.dart';

/// The full result of a category resolution attempt — a [CategorySuggestion]
/// (reused as-is from the existing suggester machinery, never replaced) plus
/// the confidence tier and itemized evidence this module adds on top.
class MerchantCategoryResolution {
  const MerchantCategoryResolution({
    required this.suggestion,
    required this.confidenceLevel,
    required this.evidence,
  });

  const MerchantCategoryResolution.unknown()
    : suggestion = null,
      confidenceLevel = MerchantConfidenceLevel.unknown,
      evidence = const MerchantEvidence.none();

  final CategorySuggestion? suggestion;
  final MerchantConfidenceLevel confidenceLevel;
  final MerchantEvidence evidence;

  bool get isUnknown => suggestion == null;
}

/// Resolves a category using, in order:
///
/// 1. **User history + the existing narrow seed catalog** — delegated
///    verbatim to `MerchantCategorySuggester.suggest` (no smsCategory
///    passed), so this adapter never re-implements or overrides that
///    resolver's own user-history priority; it only adds tiers *around* it.
/// 2. **This module's richer [MerchantIntelligenceCatalog]** — consulted
///    only when tier 1 found nothing, using the [MerchantIdentity] already
///    resolved by [MerchantIdentityResolver] (so e.g. "Amazon Prime" maps to
///    a subscription category even though the older, narrower seed catalog
///    has no opinion on it).
/// 3. **Keyword evidence from the raw SMS body** ([CategoryKeywordMatcher])
///    — the only tier that can produce a category suggestion for a merchant
///    that is otherwise completely unrecognized (e.g. "ABC Bakery" or "XYZ
///    Fuel Station"), since the keyword lives in the message text itself
///    rather than requiring a known merchant.
/// 4. **AI-suggested category name**, if supplied — matched against the
///    user's real categories the same conservative way the existing
///    `CategoryResolver` does (case-insensitive exact name match; a name
///    that doesn't exist in the user's app is never invented).
/// 5. **Generic SMS-type fallback**, delegated to
///    `MerchantCategorySuggester.suggest` again, this time with
///    `smsCategory` passed through.
/// 6. Otherwise [MerchantCategoryResolution.unknown] — never a forced guess.
///
/// AI (tier 4) can only fill a gap tiers 1-3 left empty; it can never
/// override a result tiers 1-3 already produced, so a user's own history or
/// a known-merchant match always wins over an AI opinion, matching this
/// module's core "AI must not override strong evidence" rule.
///
/// Every tier is additionally restricted to categories consistent with
/// [transactionType] ([Category.type] is [CategoryType.both] or matches):
/// the pre-existing `MerchantCategorySuggester`'s own seed-catalog tier
/// doesn't check direction at all (only its user-history tier does — see
/// its own doc), so without this guard "₹500 received from Swiggy" (income)
/// could resolve the expense-oriented "Food & Dining" catalog hint just as
/// readily as an actual Swiggy purchase would. Rather than edit that
/// existing class, this adapter passes it a pre-filtered category list, so
/// the fix lives entirely on this side of the boundary.
class MerchantAwareCategoryResolver {
  const MerchantAwareCategoryResolver(this._suggester);

  final MerchantCategorySuggester _suggester;

  MerchantCategoryResolution resolve({
    required MerchantIdentity merchant,
    required String smsBody,
    required TransactionType transactionType,
    required List<Category> categories,
    SmsTransactionCategory? smsCategory,
    String? aiCategoryName,
  }) {
    final merchantText = merchant.displayName ?? merchant.normalizedName;
    final applicableCategories = categories
        .where(
          (c) =>
              c.type == CategoryType.both ||
              c.type.name == transactionType.name,
        )
        .toList();

    final existing = _suggester.suggest(
      merchant: merchantText,
      transactionType: transactionType,
      categories: applicableCategories,
    );
    if (existing != null) {
      final isUserHistory = existing.source == SuggestionSource.userHistory;
      return MerchantCategoryResolution(
        suggestion: existing,
        confidenceLevel: isUserHistory
            ? MerchantConfidenceLevel.high
            : MerchantConfidenceX.forEvidence(
                MerchantEvidenceKind.knownMerchantCatalog,
                merchantIsAmbiguousCategory: merchant.categoryIsAmbiguous,
              ),
        evidence: MerchantEvidence(
          kind: isUserHistory
              ? MerchantEvidenceKind.userConfirmed
              : MerchantEvidenceKind.knownMerchantCatalog,
          details: [
            isUserHistory
                ? 'user has previously chosen this category for this merchant'
                : 'existing merchant seed catalog match',
          ],
        ),
      );
    }

    if (merchant.isKnown && merchant.normalizedName != null) {
      final entry = MerchantIntelligenceCatalog.lookup(
        merchant.normalizedName!,
      );
      if (entry != null) {
        final name = _resolveByName(entry.categoryHints, applicableCategories);
        if (name != null) {
          return MerchantCategoryResolution(
            suggestion: CategorySuggestion(
              categoryId: name,
              source: SuggestionSource.knownMerchant,
            ),
            confidenceLevel: MerchantConfidenceX.forEvidence(
              MerchantEvidenceKind.knownMerchantCatalog,
              merchantIsAmbiguousCategory: entry.categoryIsAmbiguous,
            ),
            evidence: MerchantEvidence(
              kind: MerchantEvidenceKind.knownMerchantCatalog,
              details: [
                'catalog entry "${entry.displayName}" suggests "$name"',
              ],
            ),
          );
        }
      }
    }

    for (final hit in CategoryKeywordMatcher.findAll(smsBody)) {
      final name = _resolveByName(hit.categoryHints, applicableCategories);
      if (name != null) {
        return MerchantCategoryResolution(
          suggestion: CategorySuggestion(
            categoryId: name,
            source: SuggestionSource.smsType,
          ),
          confidenceLevel: MerchantConfidenceLevel.medium,
          evidence: MerchantEvidence(
            kind: MerchantEvidenceKind.keywordMatch,
            details: [
              'keyword "${hit.keyword}" found in message suggests "$name"',
            ],
          ),
        );
      }
    }

    final trimmedAiCategory = aiCategoryName?.trim();
    if (trimmedAiCategory != null && trimmedAiCategory.isNotEmpty) {
      final name = _resolveByName([trimmedAiCategory], applicableCategories);
      if (name != null) {
        return MerchantCategoryResolution(
          suggestion: CategorySuggestion(
            categoryId: name,
            source: SuggestionSource.aiInference,
          ),
          confidenceLevel: MerchantConfidenceLevel.low,
          evidence: MerchantEvidence(
            kind: MerchantEvidenceKind.aiInference,
            details: ['AI suggested category "$trimmedAiCategory"'],
          ),
        );
      }
    }

    final fallback = _suggester.suggest(
      merchant: merchantText,
      transactionType: transactionType,
      categories: applicableCategories,
      smsCategory: smsCategory,
    );
    if (fallback != null) {
      return MerchantCategoryResolution(
        suggestion: fallback,
        confidenceLevel: MerchantConfidenceLevel.low,
        evidence: MerchantEvidence(
          kind: MerchantEvidenceKind.regex,
          details: [
            'generic SMS-type fallback (${smsCategory?.name ?? 'none'})',
          ],
        ),
      );
    }

    return const MerchantCategoryResolution.unknown();
  }

  String? _resolveByName(
    List<String> candidateNames,
    List<Category> categories,
  ) {
    for (final candidate in candidateNames) {
      for (final category in categories) {
        if (category.name.toLowerCase() == candidate.toLowerCase())
          return category.id;
      }
    }
    return null;
  }
}
