import '../merchant/merchant_key.dart';
import 'merchant_type.dart';

/// One known merchant's catalog record — richer than the legacy
/// `MerchantSeedCatalog` (which only maps a merchant key to candidate
/// *category names*): this also carries name aliases, VPA local-part
/// aliases, [merchantType], and category hints, backing
/// [MerchantIdentityResolver] rather than `CategoryResolver` directly (the
/// legacy seed catalog keeps doing that job unchanged — see
/// `MerchantCatalog`'s own doc comment for why these two catalogs coexist).
class MerchantCatalogEntry {
  const MerchantCatalogEntry({
    required this.canonicalName,
    this.aliases = const [],
    this.vpaAliases = const [],
    this.merchantType = MerchantType.business,
    this.possibleCategoryNames = const [],
  });

  /// The display name shown to the user, e.g. `"Swiggy"`.
  final String canonicalName;

  /// Additional normalized-key text aliases beyond [canonicalName] itself
  /// (which is always matched too) — e.g. `"swiggy india"`.
  final List<String> aliases;

  /// Normalized VPA local-part aliases — e.g. `"swiggy"` matches
  /// `swiggy@icici`, `swiggy.food@hdfcbank`, etc. via a startsWith check
  /// (see [MerchantCatalog.lookupByVpaLocalPart]).
  final List<String> vpaAliases;

  final MerchantType merchantType;

  /// Candidate category *names* this merchant could plausibly belong to —
  /// informational only (surfaced via `MerchantIdentity.possibleCategoryNames`
  /// for evidence/debugging); actual category resolution still goes through
  /// the existing `CategoryResolver`/`MerchantCategorySuggester` stack
  /// unchanged. Deliberately a list, not one value: `Amazon` alone doesn't
  /// tell you Shopping vs. Groceries vs. Subscriptions — see
  /// `CreditCardSemantics`-style contextual resolution for why the
  /// transaction's own text still has the final say.
  final List<String> possibleCategoryNames;
}

/// An extensible catalog of well-known Indian merchants, used by
/// [MerchantIdentityResolver] to resolve a *display identity* (name, type,
/// evidence) — never a category. Deliberately kept separate from the legacy
/// `MerchantSeedCatalog` (`merchant/merchant_seed_catalog.dart`), which
/// already does one job well (merchant key → candidate category names) and
/// stays exactly as-is per this feature's "don't rewrite what already
/// works" rule; this catalog answers a different question ("who is this,
/// and how sure are we") that Phase 1/2 never needed to ask.
///
/// Matching is exact on the normalized key (via `MerchantKey.normalize`,
/// the same conservative normalizer the rest of this feature already uses)
/// — never a substring/fuzzy match, so `ABC Bakery`/`ABC Electronics`/
/// `ABC Traders` never collide just because they share "abc".
abstract class MerchantCatalog {
  MerchantCatalog._();

  static final List<MerchantCatalogEntry> _entries = [
    const MerchantCatalogEntry(
      canonicalName: 'Swiggy',
      aliases: ['swiggy india', 'swiggy instamart'],
      vpaAliases: ['swiggy'],
      possibleCategoryNames: ['Food & Dining', 'Food', 'Groceries'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Zomato',
      aliases: ['zomato india'],
      vpaAliases: ['zomato'],
      possibleCategoryNames: ['Food & Dining', 'Food'],
    ),
    const MerchantCatalogEntry(
      canonicalName: "Domino's",
      aliases: ['dominos', "dominos pizza"],
      vpaAliases: ['dominos'],
      possibleCategoryNames: ['Food & Dining', 'Food'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Amazon',
      aliases: ['amazon india', 'amazon.in', 'amazon retail'],
      vpaAliases: ['amazon', 'amazonpay'],
      possibleCategoryNames: [
        'Shopping',
        'Groceries',
        'Subscriptions',
        'Entertainment',
      ],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Flipkart',
      aliases: ['flipkart india'],
      vpaAliases: ['flipkart'],
      possibleCategoryNames: ['Shopping'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Myntra',
      vpaAliases: ['myntra'],
      possibleCategoryNames: ['Shopping'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Ajio',
      vpaAliases: ['ajio'],
      possibleCategoryNames: ['Shopping'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Uber',
      aliases: ['uber india'],
      vpaAliases: ['uber'],
      possibleCategoryNames: ['Transport', 'Travel'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Ola',
      aliases: ['ola cabs', 'olacabs'],
      vpaAliases: ['ola', 'olacabs'],
      possibleCategoryNames: ['Transport', 'Travel'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Netflix',
      vpaAliases: ['netflix'],
      possibleCategoryNames: ['Entertainment', 'Subscriptions'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Spotify',
      vpaAliases: ['spotify'],
      possibleCategoryNames: ['Entertainment', 'Subscriptions'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Jio',
      aliases: ['reliance jio', 'jio mart'],
      vpaAliases: ['jio', 'myjio'],
      possibleCategoryNames: ['Bills & Utilities', 'Shopping'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Airtel',
      aliases: ['bharti airtel', 'airtel payments bank'],
      vpaAliases: ['airtel'],
      possibleCategoryNames: ['Bills & Utilities'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'BSNL',
      vpaAliases: ['bsnl'],
      possibleCategoryNames: ['Bills & Utilities'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'BigBasket',
      aliases: ['big basket'],
      vpaAliases: ['bigbasket'],
      possibleCategoryNames: ['Groceries'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Blinkit',
      aliases: ['blink it', 'grofers'],
      vpaAliases: ['blinkit', 'grofers'],
      possibleCategoryNames: ['Groceries'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Zepto',
      vpaAliases: ['zepto', 'zeptonow'],
      possibleCategoryNames: ['Groceries'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'DMart',
      aliases: ['d mart', 'avenue supermarts'],
      vpaAliases: ['dmart'],
      possibleCategoryNames: ['Groceries', 'Shopping'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Indian Oil',
      aliases: ['indianoil', 'iocl'],
      vpaAliases: ['indianoil', 'iocl'],
      possibleCategoryNames: ['Fuel', 'Transport'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'HPCL',
      aliases: ['hindustan petroleum'],
      vpaAliases: ['hpcl'],
      possibleCategoryNames: ['Fuel', 'Transport'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Shell',
      aliases: ['shell india'],
      vpaAliases: ['shell'],
      possibleCategoryNames: ['Fuel', 'Transport'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'PharmEasy',
      vpaAliases: ['pharmeasy'],
      possibleCategoryNames: ['Health', 'Healthcare'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'BookMyShow',
      aliases: ['book my show'],
      vpaAliases: ['bookmyshow', 'bms'],
      possibleCategoryNames: ['Entertainment'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'IRCTC',
      aliases: ['indian railways'],
      vpaAliases: ['irctc'],
      possibleCategoryNames: ['Travel', 'Transport'],
    ),
    const MerchantCatalogEntry(
      canonicalName: 'Starbucks',
      vpaAliases: ['starbucks'],
      possibleCategoryNames: ['Food & Dining'],
    ),
  ];

  static final Map<String, MerchantCatalogEntry> _byNameKey = {
    for (final entry in _entries) ...{
      MerchantKey.normalize(entry.canonicalName)!: entry,
      for (final alias in entry.aliases) MerchantKey.normalize(alias)!: entry,
    },
  };

  /// Sorted longest-first so a more specific alias (`swiggy instamart`)
  /// matches before a shorter one (`swiggy`) when both are prefixes of the
  /// same VPA local part.
  static final List<MapEntry<String, MerchantCatalogEntry>> _vpaAliasesSorted =
      [
        for (final entry in _entries)
          for (final alias in entry.vpaAliases)
            MapEntry(alias.toLowerCase(), entry),
      ]..sort((a, b) => b.key.length.compareTo(a.key.length));

  /// Exact normalized-key lookup — mirrors `MerchantSeedCatalog`'s own
  /// "never a substring match" invariant.
  static MerchantCatalogEntry? lookupByText(String? merchantText) {
    final key = MerchantKey.normalize(merchantText);
    if (key == null) return null;
    return _byNameKey[key];
  }

  /// A VPA local part (e.g. `"swiggy"` from `swiggy@icici`, or
  /// `"swiggy.food123"`) matches when it *starts with* a known alias — real
  /// merchant VPAs routinely append store/order suffixes
  /// (`swiggy.blr@icici`, `swiggyfood@ybl`), which a strict equality check
  /// would miss. Still never a bare substring match: `"myswiggystore"`
  /// would not match `"swiggy"` since it doesn't *start* with it — avoiding
  /// the same over-merging risk `MerchantKey` already guards against.
  static MerchantCatalogEntry? lookupByVpaLocalPart(String localPart) {
    final lower = localPart.toLowerCase();
    for (final aliasEntry in _vpaAliasesSorted) {
      if (lower.startsWith(aliasEntry.key)) return aliasEntry.value;
    }
    return null;
  }
}
