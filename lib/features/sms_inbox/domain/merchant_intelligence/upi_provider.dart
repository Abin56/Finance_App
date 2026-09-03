/// The UPI app/rail a payment moved over — e.g. PhonePe, Google Pay, Paytm —
/// as distinct from the actual merchant paid. A VPA handle
/// (`@ybl`/`@okhdfcbank`/`@paytm`/...) is a hint about *which app or bank*
/// issued the payer's or payee's VPA, not who the payee is: `swiggy@upi` and
/// `swiggy@ybl` can both be Swiggy. See [MerchantIdentity.paymentProvider]
/// for why this is always kept off the merchant field.
enum UpiProvider {
  phonePe,
  googlePay,
  paytm,
  amazonPay,
  mobikwik,
  freecharge,
  cred,

  /// A recognized bank-issued UPI handle (e.g. `@oksbi`, `@okicici`) rather
  /// than a third-party app — still "who moved the money," just a bank
  /// instead of an app.
  bankUpi,

  unknown,
}

extension UpiProviderX on UpiProvider {
  String get label {
    switch (this) {
      case UpiProvider.phonePe:
        return 'PhonePe';
      case UpiProvider.googlePay:
        return 'Google Pay';
      case UpiProvider.paytm:
        return 'Paytm';
      case UpiProvider.amazonPay:
        return 'Amazon Pay';
      case UpiProvider.mobikwik:
        return 'MobiKwik';
      case UpiProvider.freecharge:
        return 'Freecharge';
      case UpiProvider.cred:
        return 'CRED';
      case UpiProvider.bankUpi:
        return 'Bank UPI';
      case UpiProvider.unknown:
        return 'Unknown';
    }
  }
}

/// Resolves a UPI provider from two independent kinds of evidence, kept
/// separate because they answer different questions:
///
/// - [fromHandle]: the `@handle` suffix of a VPA — identifies *whose* VPA
///   namespace this is (an app's or a bank's), not necessarily which app the
///   payer actually tapped "pay" in.
/// - [fromMentionInText]: an explicit app name mentioned in the SMS body
///   itself (e.g. "Paid using PhonePe to ...") — stronger, first-person
///   evidence of the rail actually used.
abstract class UpiProviderResolver {
  UpiProviderResolver._();

  /// Handle suffix (without the leading `@`, case-insensitive) -> provider.
  /// Deliberately conservative: only handles with an unambiguous, widely
  /// documented owner are mapped; anything else resolves to
  /// [UpiProvider.unknown] rather than a guess.
  static const Map<String, UpiProvider> _handleMap = {
    'ybl': UpiProvider.phonePe,
    'phonepe': UpiProvider.phonePe,
    'okhdfcbank': UpiProvider.bankUpi,
    'okicici': UpiProvider.bankUpi,
    'oksbi': UpiProvider.bankUpi,
    'okaxis': UpiProvider.bankUpi,
    'paytm': UpiProvider.paytm,
    'pty': UpiProvider.paytm,
    'apl': UpiProvider.amazonPay,
    'amazonpay': UpiProvider.amazonPay,
    'ibl': UpiProvider.bankUpi,
    'axl': UpiProvider.bankUpi,
    'okbizaxis': UpiProvider.bankUpi,
  };

  static UpiProvider fromHandle(String? handle) {
    if (handle == null || handle.isEmpty) return UpiProvider.unknown;
    return _handleMap[handle.toLowerCase()] ?? UpiProvider.unknown;
  }

  static final List<({RegExp pattern, UpiProvider provider})> _textPatterns = [
    (
      pattern: RegExp(r'\bphonepe\b', caseSensitive: false),
      provider: UpiProvider.phonePe,
    ),
    (
      pattern: RegExp(r'\b(google\s*pay|g\s*pay|gpay)\b', caseSensitive: false),
      provider: UpiProvider.googlePay,
    ),
    (
      pattern: RegExp(r'\bpaytm\b', caseSensitive: false),
      provider: UpiProvider.paytm,
    ),
    (
      pattern: RegExp(r'\bamazon\s*pay\b', caseSensitive: false),
      provider: UpiProvider.amazonPay,
    ),
    (
      pattern: RegExp(r'\bmobikwik\b', caseSensitive: false),
      provider: UpiProvider.mobikwik,
    ),
    (
      pattern: RegExp(r'\bfreecharge\b', caseSensitive: false),
      provider: UpiProvider.freecharge,
    ),
    (
      pattern: RegExp(r'\bcred\b', caseSensitive: false),
      provider: UpiProvider.cred,
    ),
  ];

  /// Scans free-form SMS/description text for an explicit app mention. Only
  /// used as *provider* evidence — callers must never treat a match here as
  /// the merchant (see [MerchantIdentityResolver]).
  static UpiProvider fromMentionInText(String body) {
    for (final entry in _textPatterns) {
      if (entry.pattern.hasMatch(body)) return entry.provider;
    }
    return UpiProvider.unknown;
  }

  /// Normalized tokens that name a payment app/provider rather than a real
  /// merchant — used to stop a regex merchant-guess of e.g. "Paytm" (from a
  /// message with no real payee name) from being treated as a business.
  /// Kept independent of `MerchantKey`'s own noise-token list (which strips
  /// these same words for a different reason — collapsing formatting noise
  /// within an already-identified merchant string, not merchant-identity
  /// detection).
  static const Set<String> providerNameTokens = {
    'phonepe',
    'googlepay',
    'gpay',
    'paytm',
    'amazonpay',
    'mobikwik',
    'freecharge',
    'cred',
  };
}
