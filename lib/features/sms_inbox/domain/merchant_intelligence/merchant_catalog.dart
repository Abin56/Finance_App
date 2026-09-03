import 'merchant_type.dart';

/// One entry in [MerchantIntelligenceCatalog] — a business FlowFi can name
/// with confidence, plus what it implies (and doesn't imply) about category.
class MerchantCatalogEntry {
  const MerchantCatalogEntry({
    required this.displayName,
    required this.merchantType,
    required this.categoryHints,
    this.subcategory,
    this.categoryIsAmbiguous = false,
  });

  /// The human-readable name to show, e.g. `'Swiggy'` — never longer or
  /// more specific than what the catalog entry actually represents (e.g.
  /// the `'Amazon Prime'` entry's [displayName] is `'Amazon Prime'`, not
  /// just `'Amazon'`, so a subscription charge doesn't get relabeled as a
  /// generic Amazon purchase).
  final String displayName;

  final MerchantType merchantType;

  /// Ordered candidate FlowFi category names — resolved against the user's
  /// *actual* categories the same way `MerchantSeedCatalog` already does
  /// (first name that matches a real category wins); never invents a
  /// category that doesn't exist in the user's app.
  final List<String> categoryHints;

  /// A finer-grained label than any FlowFi category, shown alongside the
  /// resolved category rather than replacing it (e.g. `'Food delivery'` next
  /// to a resolved `'Food & Dining'` category).
  final String? subcategory;

  /// True when this exact entry's real-world category genuinely depends on
  /// context this catalog can't see (the canonical example being bare
  /// `'Amazon'`, which could be shopping, groceries, or a subscription) —
  /// used to cap confidence at [MerchantConfidenceLevel.medium] even though
  /// the merchant identity itself is confidently known. Variant entries that
  /// disambiguate the same brand (e.g. `'Amazon Prime'`) set this `false`.
  final bool categoryIsAmbiguous;
}

/// An extensible catalog of merchants FlowFi can name with confidence,
/// keyed by `MerchantKey.normalize`'d strings so lookups agree with the rest
/// of the pipeline's normalization (the same conservative rules that keep
/// "ABC Restaurant" and "ABC Electronics" apart also keep "Amazon" and
/// "Amazon Fresh" apart here — see `MerchantKey`'s doc comment).
///
/// Deliberately separate from `MerchantSeedCatalog` (which only maps a
/// normalized key to candidate *category* names for the existing
/// `MerchantCategorySuggester`): this catalog is about merchant *identity*
/// (display name, business type) first, and only offers category hints as a
/// secondary, clearly-flagged-when-ambiguous signal — see
/// [MerchantCatalogEntry.categoryIsAmbiguous] and this module's "merchant
/// identification and category identification must be separate" mandate.
abstract class MerchantIntelligenceCatalog {
  MerchantIntelligenceCatalog._();

  static final Map<String, MerchantCatalogEntry> _entries = {
    // --- Food delivery / dining -------------------------------------------
    'swiggy': const MerchantCatalogEntry(
      displayName: 'Swiggy',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Food & Dining', 'Food'],
      subcategory: 'Food delivery',
    ),
    'swiggy instamart': const MerchantCatalogEntry(
      displayName: 'Swiggy Instamart',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Groceries', 'Shopping'],
      subcategory: 'Grocery delivery',
    ),
    'zomato': const MerchantCatalogEntry(
      displayName: 'Zomato',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Food & Dining', 'Food'],
      subcategory: 'Food delivery',
    ),
    'dominos': const MerchantCatalogEntry(
      displayName: "Domino's",
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Food & Dining', 'Food'],
      subcategory: 'Restaurant',
    ),
    'starbucks': const MerchantCatalogEntry(
      displayName: 'Starbucks',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Food & Dining', 'Food'],
      subcategory: 'Cafe',
    ),
    'mcdonalds': const MerchantCatalogEntry(
      displayName: "McDonald's",
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Food & Dining', 'Food'],
      subcategory: 'Fast food',
    ),

    // --- Groceries ----------------------------------------------------------
    'blinkit': const MerchantCatalogEntry(
      displayName: 'Blinkit',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Groceries', 'Shopping'],
      subcategory: 'Grocery delivery',
    ),
    'zepto': const MerchantCatalogEntry(
      displayName: 'Zepto',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Groceries', 'Shopping'],
      subcategory: 'Grocery delivery',
    ),
    'bigbasket': const MerchantCatalogEntry(
      displayName: 'BigBasket',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Groceries', 'Shopping'],
      subcategory: 'Grocery delivery',
    ),
    'dmart': const MerchantCatalogEntry(
      displayName: 'DMart',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Groceries', 'Shopping'],
      subcategory: 'Supermarket',
    ),

    // --- Amazon variants: identity is always "Amazon <something>"; category
    //     is intentionally NOT collapsed to one answer — see class doc.
    'amazon': const MerchantCatalogEntry(
      displayName: 'Amazon',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Shopping'],
      categoryIsAmbiguous: true,
    ),
    'amazon prime': const MerchantCatalogEntry(
      displayName: 'Amazon Prime',
      merchantType: MerchantType.subscription,
      categoryHints: ['Entertainment', 'Subscriptions'],
      subcategory: 'Streaming subscription',
    ),
    'amazon pay': const MerchantCatalogEntry(
      displayName: 'Amazon Pay',
      merchantType: MerchantType.paymentProvider,
      categoryHints: [],
    ),
    'amazon fresh': const MerchantCatalogEntry(
      displayName: 'Amazon Fresh',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Groceries', 'Shopping'],
      subcategory: 'Grocery delivery',
    ),
    'amazon marketplace': const MerchantCatalogEntry(
      displayName: 'Amazon Marketplace',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Shopping'],
      categoryIsAmbiguous: true,
    ),

    // --- Google variants: same principle — "Google" alone is ambiguous;
    //     specific products are not.
    'google play': const MerchantCatalogEntry(
      displayName: 'Google Play',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Entertainment', 'Shopping'],
      categoryIsAmbiguous: true,
      subcategory: 'Digital purchase',
    ),
    'google one': const MerchantCatalogEntry(
      displayName: 'Google One',
      merchantType: MerchantType.subscription,
      categoryHints: ['Subscriptions', 'Bills & Utilities'],
      subcategory: 'Cloud storage subscription',
    ),
    'google cloud': const MerchantCatalogEntry(
      displayName: 'Google Cloud',
      merchantType: MerchantType.subscription,
      categoryHints: ['Subscriptions', 'Bills & Utilities'],
      subcategory: 'Cloud services',
    ),
    'google workspace': const MerchantCatalogEntry(
      displayName: 'Google Workspace',
      merchantType: MerchantType.subscription,
      categoryHints: ['Subscriptions', 'Bills & Utilities'],
      subcategory: 'Productivity subscription',
    ),
    // Note: "Google Pay" is deliberately NOT a catalog entry — it's a
    // payment provider (see UpiProviderResolver), not a merchant.

    // --- Apple variants -------------------------------------------------
    'apple': const MerchantCatalogEntry(
      displayName: 'Apple',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Shopping', 'Electronics'],
      categoryIsAmbiguous: true,
    ),
    'apple music': const MerchantCatalogEntry(
      displayName: 'Apple Music',
      merchantType: MerchantType.subscription,
      categoryHints: ['Entertainment', 'Subscriptions'],
      subcategory: 'Streaming subscription',
    ),
    'apple store': const MerchantCatalogEntry(
      displayName: 'Apple Store',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Shopping', 'Electronics'],
      subcategory: 'Electronics',
    ),
    'app store': const MerchantCatalogEntry(
      displayName: 'App Store',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Entertainment', 'Shopping'],
      categoryIsAmbiguous: true,
      subcategory: 'Digital purchase',
    ),
    'icloud': const MerchantCatalogEntry(
      displayName: 'iCloud',
      merchantType: MerchantType.subscription,
      categoryHints: ['Subscriptions', 'Bills & Utilities'],
      subcategory: 'Cloud storage subscription',
    ),

    // --- General shopping -------------------------------------------------
    'flipkart': const MerchantCatalogEntry(
      displayName: 'Flipkart',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Shopping'],
    ),
    'myntra': const MerchantCatalogEntry(
      displayName: 'Myntra',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Shopping'],
      subcategory: 'Clothing',
    ),
    'ajio': const MerchantCatalogEntry(
      displayName: 'Ajio',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Shopping'],
      subcategory: 'Clothing',
    ),

    // --- Transport / travel -------------------------------------------------
    'uber': const MerchantCatalogEntry(
      displayName: 'Uber',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Transport', 'Transportation'],
      subcategory: 'Taxi',
    ),
    'ola': const MerchantCatalogEntry(
      displayName: 'Ola',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Transport', 'Transportation'],
      subcategory: 'Taxi',
    ),

    // --- Fuel -----------------------------------------------------------
    'indian oil': const MerchantCatalogEntry(
      displayName: 'Indian Oil',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Fuel', 'Transport'],
    ),
    'hpcl': const MerchantCatalogEntry(
      displayName: 'HPCL',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Fuel', 'Transport'],
    ),
    'bharat petroleum': const MerchantCatalogEntry(
      displayName: 'Bharat Petroleum',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Fuel', 'Transport'],
    ),
    'shell': const MerchantCatalogEntry(
      displayName: 'Shell',
      merchantType: MerchantType.knownBusiness,
      categoryHints: ['Fuel', 'Transport'],
    ),

    // --- Subscriptions ----------------------------------------------------
    'netflix': const MerchantCatalogEntry(
      displayName: 'Netflix',
      merchantType: MerchantType.subscription,
      categoryHints: ['Entertainment', 'Subscriptions'],
      subcategory: 'Streaming subscription',
    ),
    'spotify': const MerchantCatalogEntry(
      displayName: 'Spotify',
      merchantType: MerchantType.subscription,
      categoryHints: ['Entertainment', 'Subscriptions'],
      subcategory: 'Streaming subscription',
    ),

    // --- Utilities / telecom ------------------------------------------------
    'jio': const MerchantCatalogEntry(
      displayName: 'Jio',
      merchantType: MerchantType.utility,
      categoryHints: ['Bills & Utilities', 'Utilities'],
      subcategory: 'Mobile',
    ),
    'airtel': const MerchantCatalogEntry(
      displayName: 'Airtel',
      merchantType: MerchantType.utility,
      categoryHints: ['Bills & Utilities', 'Utilities'],
      subcategory: 'Mobile',
    ),
    'bsnl': const MerchantCatalogEntry(
      displayName: 'BSNL',
      merchantType: MerchantType.utility,
      categoryHints: ['Bills & Utilities', 'Utilities'],
      subcategory: 'Mobile',
    ),
  };

  /// Exact-key lookup only — no fuzzy/substring matching, mirroring
  /// `MerchantSeedCatalog`'s own deliberately conservative approach (see its
  /// doc comment: guessing at partial matches is how unrelated businesses
  /// get merged).
  static MerchantCatalogEntry? lookup(String normalizedKey) =>
      _entries[normalizedKey];

  /// True when [normalizedKey] is a payment provider's own name rather than
  /// a real merchant — i.e. it resolved to a [MerchantCatalogEntry] whose
  /// [MerchantCatalogEntry.merchantType] is [MerchantType.paymentProvider],
  /// OR it's a bare provider-app token from [UpiProviderResolver].
  static bool isPaymentProviderName(String normalizedKey) {
    final entry = _entries[normalizedKey];
    if (entry != null)
      return entry.merchantType == MerchantType.paymentProvider;
    return false;
  }
}
