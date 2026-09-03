import '../merchant/merchant_key.dart';

/// Refuses to let a payment rail/app (PhonePe, Google Pay, ...) be learned or
/// stored as if it were a merchant — mirrors `PaymentProvider`'s doc comment:
/// the rail that moved the money is never the counterparty being paid.
/// `MerchantKey.normalize` already strips a few provider-shaped noise tokens
/// (`paytm`, `razorpay`) as payment-rail noise, but survivors like "PhonePe"
/// or "Google Pay" have no other reason to be stripped, so this guard exists
/// to catch those explicitly before they ever reach a learning store.
abstract class MerchantProviderGuard {
  MerchantProviderGuard._();

  static const Set<String> _providerKeys = {
    'phonepe',
    'phone pe',
    'googlepay',
    'google pay',
    'gpay',
    'bhim',
    'cred',
    'whatsapp pay',
    'whatsapppay',
    'amazonpay',
    'amazon pay',
  };

  /// True when [raw] (or its normalized `MerchantKey`) identifies a known
  /// payment provider rather than a real merchant.
  static bool isProviderName(String? raw) {
    if (raw == null) return false;
    final lower = raw.toLowerCase().trim();
    if (_providerKeys.contains(lower)) return true;

    final key = MerchantKey.normalize(raw);
    return key != null && _providerKeys.contains(key);
  }
}
