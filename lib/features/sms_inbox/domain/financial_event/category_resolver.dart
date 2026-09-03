import '../../../categories/domain/category.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../merchant/merchant_category_suggester.dart';
import '../sms_transaction_category.dart';

/// Wraps [MerchantCategorySuggester] with two extra tiers on top — never a
/// replacement for it. Full priority order:
///
/// 1-2. User history, then the seed catalog — delegated verbatim to
///    [MerchantCategorySuggester.suggest] (no `smsCategory`, so its own
///    tier-4 fallback never fires inside that call).
/// 3. AI category inference, only with grounded evidence (the caller is
///    responsible for only passing [aiCategoryName] once
///    `EvidenceGrounding` has confirmed it — see `FinancialEventExtractor`).
///    Resolved by exact (case-insensitive) match against the user's *real*
///    [Category] list only — never invents one that doesn't exist.
/// 4. Contextual semantic evidence — a small, deterministic set of
///    business-type keywords appearing directly in the merchant/
///    counterparty *name* itself (e.g. "Spice Route Restaurant" contains
///    "Restaurant"). Deliberately kept local to this class rather than
///    [MerchantCategorySuggester] itself: that class is also consumed by
///    the separate `merchant_intelligence` module with its own, different
///    confidence grading for a keyword-shaped hit, so adding it there would
///    silently change that module's confidence levels too.
/// 5. Generic SMS-type fallback, delegated to
///    [MerchantCategorySuggester.suggest] again, this time with
///    `smsCategory` passed through.
/// 6. Otherwise no suggestion — never a forced guess.
class CategoryResolver {
  const CategoryResolver(this._suggester);

  final MerchantCategorySuggester _suggester;

  /// See this class's doc comment, tier 4. Still resolved through
  /// [_resolveByName] against the user's real categories, so this can
  /// never invent a category that doesn't exist, exactly like every other
  /// tier here.
  static final Map<RegExp, List<String>> _contextualKeywords = {
    RegExp(
      r'\b(restaurant|cafe|café|dhaba|eatery|diner)\b',
      caseSensitive: false,
    ): [
      'Food & Dining',
      'Food',
    ],
    RegExp(r'\b(pharmacy|hospital|clinic|medical)\b', caseSensitive: false): [
      'Health',
      'Healthcare',
      'Medical',
    ],
    RegExp(r'\b(petrol|fuel|gas station)\b', caseSensitive: false): [
      'Fuel',
      'Transport',
    ],
    RegExp(r'\b(supermarket|kirana|grocer[sy]?)\b', caseSensitive: false): [
      'Groceries',
      'Shopping',
    ],
  };

  CategorySuggestion? resolve({
    required String? merchant,
    required TransactionType transactionType,
    required List<Category> categories,
    SmsTransactionCategory? smsCategory,
    String? aiCategoryName,
  }) {
    if (categories.isEmpty) return null;

    // Tiers 1-2: user history, then the seed catalog — pass no smsCategory
    // so `_fromSmsCategory` never fires inside this call; the ai/keyword/
    // smsType tiers below are ordered explicitly by this method instead.
    final fromHistoryOrCatalog = _suggester.suggest(
      merchant: merchant,
      transactionType: transactionType,
      categories: categories,
    );
    if (fromHistoryOrCatalog != null) return fromHistoryOrCatalog;

    if (aiCategoryName != null && aiCategoryName.trim().isNotEmpty) {
      final match = _resolveByName(aiCategoryName, categories);
      if (match != null)
        return CategorySuggestion(
          categoryId: match,
          source: SuggestionSource.aiInference,
        );
    }

    final fromKeyword = _fromContextualKeyword(merchant, categories);
    if (fromKeyword != null) return fromKeyword;

    return _suggester.suggest(
      merchant: merchant,
      transactionType: transactionType,
      categories: categories,
      smsCategory: smsCategory,
    );
  }

  CategorySuggestion? _fromContextualKeyword(
    String? merchant,
    List<Category> categories,
  ) {
    if (merchant == null || merchant.trim().isEmpty) return null;
    for (final entry in _contextualKeywords.entries) {
      if (entry.key.hasMatch(merchant)) {
        for (final name in entry.value) {
          final id = _resolveByName(name, categories);
          if (id != null) {
            return CategorySuggestion(
              categoryId: id,
              source: SuggestionSource.knownMerchant,
            );
          }
        }
      }
    }
    return null;
  }

  String? _resolveByName(String name, List<Category> categories) {
    for (final category in categories) {
      if (category.name.toLowerCase() == name.toLowerCase()) return category.id;
    }
    return null;
  }
}
