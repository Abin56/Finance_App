/// A small starter map of well-known merchants to the *category names* they
/// usually belong to, so a brand-new user's first Swiggy SMS already suggests
/// Food & Dining rather than nothing.
///
/// Three deliberate limits keep this honest:
///
///  * It yields category *names*, never ids. `MerchantCategorySuggester`
///    resolves them against the user's own category list, so this can only
///    ever point at a category that genuinely exists — it never invents one,
///    and a user who deleted "Food & Dining" simply gets no suggestion.
///  * The user's own history always outranks it (see the suggester), so a
///    seed is only ever a first guess, overridden the moment the user
///    disagrees once.
///  * Matching is exact on the normalized key, never a substring. `AMAZON`
///    must not silently claim `AMAZON PAY`, which is a different rail with a
///    different natural category.
///
/// Names are matched case-insensitively against the user's categories, and
/// several candidates are listed per merchant because FlowFi's default
/// category set and a user's renamed set can both be right.
abstract class MerchantSeedCatalog {
  MerchantSeedCatalog._();

  /// Keys here are already `MerchantKey.normalize`d (lowercase, no
  /// punctuation, rail/legal noise stripped) — the suggester looks up a
  /// normalized key directly, so these must be stored in the same shape.
  static const Map<String, List<String>> _seeds = {
    // Food delivery / dining
    'swiggy': ['Food & Dining', 'Food'],
    'zomato': ['Food & Dining', 'Food'],
    'dominos': ['Food & Dining', 'Food'],
    'mcdonalds': ['Food & Dining', 'Food'],
    'starbucks': ['Food & Dining', 'Food'],
    'blinkit': ['Groceries', 'Food & Dining'],
    'zepto': ['Groceries', 'Food & Dining'],
    'bigbasket': ['Groceries', 'Food & Dining'],

    // Shopping
    'amazon': ['Shopping'],
    'flipkart': ['Shopping'],
    'myntra': ['Shopping'],
    'ajio': ['Shopping'],
    'meesho': ['Shopping'],
    'nykaa': ['Shopping'],

    // Transport
    'uber': ['Transport', 'Travel'],
    'ola': ['Transport', 'Travel'],
    'rapido': ['Transport', 'Travel'],
    'irctc': ['Travel', 'Transport'],
    'indigo': ['Travel', 'Transport'],
    'redbus': ['Travel', 'Transport'],

    // Fuel
    'indian oil': ['Fuel', 'Transport'],
    'bharat petroleum': ['Fuel', 'Transport'],
    'hp': ['Fuel', 'Transport'],
    'shell': ['Fuel', 'Transport'],

    // Entertainment / subscriptions
    'netflix': ['Entertainment', 'Subscriptions'],
    'spotify': ['Entertainment', 'Subscriptions'],
    'hotstar': ['Entertainment', 'Subscriptions'],
    'bookmyshow': ['Entertainment'],
    'youtube': ['Entertainment', 'Subscriptions'],
    'prime video': ['Entertainment', 'Subscriptions'],

    // Utilities / telecom
    'airtel': ['Bills & Utilities', 'Utilities'],
    'jio': ['Bills & Utilities', 'Utilities'],
    'vodafone': ['Bills & Utilities', 'Utilities'],
    'bsnl': ['Bills & Utilities', 'Utilities'],
    'tata power': ['Bills & Utilities', 'Utilities'],
    'electricity board': ['Bills & Utilities', 'Utilities'],
    'adani electricity': ['Bills & Utilities', 'Utilities'],

    // Health
    'apollo': ['Health', 'Healthcare', 'Medical'],
    'pharmeasy': ['Health', 'Healthcare', 'Medical'],
    'practo': ['Health', 'Healthcare', 'Medical'],
  };

  /// Candidate category names for [normalizedMerchantKey], or empty when this
  /// catalog has never heard of the merchant — which is the common case and
  /// must stay a non-event, not a fallback guess.
  static List<String> categoryNamesFor(String normalizedMerchantKey) {
    return _seeds[normalizedMerchantKey] ?? const [];
  }
}
