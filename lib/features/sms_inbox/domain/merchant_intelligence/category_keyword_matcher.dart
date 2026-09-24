/// A keyword-to-category hint, plus the literal keyword that matched so the
/// caller can cite it as evidence (e.g. "category evidence: keyword
/// 'petrol'") rather than asserting a category with no stated reason.
class CategoryKeywordHit {
  const CategoryKeywordHit({
    required this.keyword,
    required this.categoryHints,
  });
  final String keyword;
  final List<String> categoryHints;
}

/// Deterministic, keyword-based category evidence for transactions with no
/// recognized merchant at all — e.g. "XYZ Fuel Station" or "ABC Bakery" carry
/// their own category evidence in the name even though neither is a known
/// business. Intentionally narrow and literal (whole-word matches on a short,
/// hand-curated list) rather than any kind of fuzzy/semantic matching — a
/// keyword hit is *supporting* evidence for an otherwise-unknown merchant,
/// never license to invent the merchant's identity itself.
abstract class CategoryKeywordMatcher {
  CategoryKeywordMatcher._();

  static final List<
    ({RegExp pattern, String keyword, List<String> categoryHints})
  >
  _rules = [
    (
      pattern: RegExp(
        r'\b(petrol|diesel|fuel\s*station|filling\s*station)\b',
        caseSensitive: false,
      ),
      keyword: 'petrol/diesel/fuel station',
      categoryHints: ['Fuel', 'Transport'],
    ),
    (
      pattern: RegExp(r'\bbaker(y|ies)\b', caseSensitive: false),
      keyword: 'bakery',
      categoryHints: ['Food & Dining', 'Food'],
    ),
    (
      pattern: RegExp(r'\b(restaurant|dhaba|eatery)\b', caseSensitive: false),
      keyword: 'restaurant',
      categoryHints: ['Food & Dining', 'Food'],
    ),
    (
      pattern: RegExp(r'\b(cafe|coffee\s*house)\b', caseSensitive: false),
      keyword: 'cafe',
      categoryHints: ['Food & Dining', 'Food'],
    ),
    (
      pattern: RegExp(
        r'\b(grocery|groceries|supermarket|kirana|mart)\b',
        caseSensitive: false,
      ),
      keyword: 'grocery/supermarket',
      categoryHints: ['Groceries', 'Shopping'],
    ),
    (
      pattern: RegExp(
        r'\b(pharmacy|medical\s*store|chemist|medicos)\b',
        caseSensitive: false,
      ),
      keyword: 'pharmacy',
      categoryHints: ['Health', 'Healthcare'],
    ),
    (
      pattern: RegExp(
        r'\b(hospital|clinic|diagnostics?)\b',
        caseSensitive: false,
      ),
      keyword: 'hospital/clinic',
      categoryHints: ['Health', 'Healthcare'],
    ),
    (
      pattern: RegExp(r'\b(parking)\b', caseSensitive: false),
      keyword: 'parking',
      categoryHints: ['Transport', 'Transportation'],
    ),
    (
      pattern: RegExp(r'\b(toll|fastag)\b', caseSensitive: false),
      keyword: 'toll/FASTag',
      categoryHints: ['Transport', 'Transportation'],
    ),
    (
      pattern: RegExp(r'\belectricity\b', caseSensitive: false),
      keyword: 'electricity',
      categoryHints: ['Bills & Utilities', 'Utilities'],
    ),
    (
      pattern: RegExp(
        r'\b(school|college|tuition|university)\s*fee',
        caseSensitive: false,
      ),
      keyword: 'school/college fee',
      categoryHints: ['Education'],
    ),
  ];

  /// Returns every rule whose keyword appears in [text], most specific rules
  /// first (declaration order) — callers typically use only the first hit.
  static List<CategoryKeywordHit> findAll(String text) {
    final hits = <CategoryKeywordHit>[];
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(text)) {
        hits.add(
          CategoryKeywordHit(
            keyword: rule.keyword,
            categoryHints: rule.categoryHints,
          ),
        );
      }
    }
    return hits;
  }
}
