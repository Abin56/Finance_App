/// Normalizes the free-text merchant string a parser lifted out of an SMS
/// into a stable lookup key, so that `SWIGGY*ORDER`, `Swiggy Ltd` and
/// `SWIGGY-BLR` all recall the same remembered category.
///
/// Deliberately conservative: it strips punctuation, payment-rail noise and
/// legal suffixes, but never stems or fuzzy-matches. Two merchants that
/// merely look similar (`AMAZON` vs `AMAZON PAY`) stay distinct keys — over-
/// merging would silently suggest the wrong category for a real, different
/// merchant, which costs the user more than simply not suggesting anything.
abstract class MerchantKey {
  MerchantKey._();

  /// Rail prefixes/suffixes banks staple onto the merchant field. These carry
  /// no merchant identity, so leaving them in would key `UPI-SWIGGY` apart
  /// from `SWIGGY` and make the memory never recall.
  static const Set<String> _noiseTokens = {
    'upi', 'pos', 'ach', 'neft', 'imps', 'rtgs', 'atm', 'ecom', 'inf', 'mmt',
    'ltd', 'limited', 'pvt', 'private', 'inc', 'llp', 'co', 'india', 'in',
    'payment', 'payments', 'paytm', 'bill', 'billdesk', 'razorpay',
  };

  /// Returns null when nothing identifying survives normalization — an empty
  /// key must never be stored or looked up, or every unparseable merchant
  /// would collide into one bucket and recall each other's categories.
  static String? normalize(String? raw) {
    if (raw == null) return null;

    final tokens = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        // A bare number is a terminal/store id, not a merchant name.
        .where((token) => !RegExp(r'^\d+$').hasMatch(token))
        .where((token) => !_noiseTokens.contains(token))
        .toList();

    if (tokens.isEmpty) return null;
    return tokens.join(' ');
  }
}
