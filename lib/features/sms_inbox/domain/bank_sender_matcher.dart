/// Maps an SMS sender id to a human-readable bank name + logo asset key.
/// Indian bank/UPI SMS senders are DLT-registered as a 2-letter prefix (the
/// telecom operator route, e.g. `VM-`, `VD-`, `AX-`, `JM-`) followed by a
/// 6-letter header — the prefix varies by region/carrier for the *same*
/// bank, so matching must strip it before comparing.
abstract class BankSenderMatcher {
  BankSenderMatcher._();

  static const Map<String, String> _headerToBankName = {
    'HDFCBK': 'HDFC Bank',
    'HDFCBN': 'HDFC Bank',
    'ICICIB': 'ICICI Bank',
    'ICICIT': 'ICICI Bank',
    'SBIBNK': 'State Bank of India',
    'SBIINB': 'State Bank of India',
    'SBIPSG': 'State Bank of India',
    'AXISBK': 'Axis Bank',
    'AXISBN': 'Axis Bank',
    'KOTAKB': 'Kotak Mahindra Bank',
    'KOTAKM': 'Kotak Mahindra Bank',
    'PNBSMS': 'Punjab National Bank',
    'CBSSBI': 'State Bank of India',
    'IDFCFB': 'IDFC FIRST Bank',
    'YESBNK': 'Yes Bank',
    'PAYTMB': 'Paytm Payments Bank',
    'AMZNPY': 'Amazon Pay',
    'BOIIND': 'Bank of India',
    'BOIBNK': 'Bank of India',
  };

  /// Bank-signature fallback for when the sender id is unrecognized (e.g.
  /// a UPI-app or numeric sender): a trailing `-BOI` signature. The bank is
  /// only a confirmation signal — the account's last-4 stays the match key.
  static final RegExp _boiSignature = RegExp(
    r'-\s*BOI\s*$',
    caseSensitive: false,
  );

  static String? bankNameFor(String sender, {String? body}) {
    final fromSender = _bankNameFromSender(sender);
    if (fromSender != null) return fromSender;
    if (body != null && _boiSignature.hasMatch(body.trim())) {
      return 'Bank of India';
    }
    return null;
  }

  /// Strips a 2-letter DLT route prefix (`VM-`, `VD-`, `AX-`, `JM-`, ...)
  /// followed by a hyphen, if present, then upper-cases the remainder.
  static String normalize(String sender) {
    final upper = sender.trim().toUpperCase();
    final match = RegExp(r'^[A-Z]{2}-(.+)$').firstMatch(upper);
    return (match?.group(1) ?? upper).replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Best-effort bank name for a sender id, or null if unrecognized (the
  /// generic parser/UI still work — this only drives the display name/logo).
  static String? _bankNameFromSender(String sender) {
    final normalized = normalize(sender);
    for (final entry in _headerToBankName.entries) {
      if (normalized.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  /// Logo asset key (e.g. `assets/icons/banks/hdfc.png`) for a bank name,
  /// falling back to a generic bank icon key when unknown. Actual asset
  /// files are a content task tracked separately from parsing logic.
  static String logoAssetKeyFor(String? bankName) {
    switch (bankName) {
      case 'HDFC Bank':
        return 'hdfc';
      case 'ICICI Bank':
        return 'icici';
      case 'State Bank of India':
        return 'sbi';
      case 'Axis Bank':
        return 'axis';
      case 'Kotak Mahindra Bank':
        return 'kotak';
      case 'Punjab National Bank':
        return 'pnb';
      case 'IDFC FIRST Bank':
        return 'idfc';
      case 'Yes Bank':
        return 'yes';
      case 'Paytm Payments Bank':
        return 'paytm';
      case 'Amazon Pay':
        return 'amazon_pay';
      default:
        return 'generic_bank';
    }
  }
}
