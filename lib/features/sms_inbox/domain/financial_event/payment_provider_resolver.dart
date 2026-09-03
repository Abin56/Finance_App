import 'payment_provider.dart';
import 'vpa_info.dart';

/// Resolves which rail/app actually moved the money — deliberately separate
/// from merchant resolution (see [PaymentProvider]'s doc comment for the
/// "PhonePe vs. Swiggy" example this class exists to get right).
///
/// Two independent signals, checked in order:
///  1. Explicit phrasing in the SMS itself ("using PhonePe", "via Google
///     Pay") — the strongest signal, since the message says so directly.
///  2. The VPA handle (`@ybl` historically routes through PhonePe,
///     `@oksbi`/`@okhdfcbank`/... through Google Pay, `@paytm` through
///     Paytm, etc.) — a much weaker signal in practice (handles are not
///     exclusively owned by one app and banks reassign them), so this is
///     only ever used when the explicit-phrasing check found nothing, and
///     even then the result should be treated as a hint, not a fact.
abstract class PaymentProviderResolver {
  PaymentProviderResolver._();

  static final Map<PaymentProvider, RegExp> _explicitPhrasePatterns = {
    PaymentProvider.phonePe: RegExp(
      r'\b(via|using|through)\s+phonepe\b',
      caseSensitive: false,
    ),
    PaymentProvider.googlePay: RegExp(
      r'\b(via|using|through)\s+(google\s?pay|gpay)\b',
      caseSensitive: false,
    ),
    PaymentProvider.paytm: RegExp(
      r'\b(via|using|through)\s+paytm\b',
      caseSensitive: false,
    ),
    PaymentProvider.amazonPay: RegExp(
      r'\b(via|using|through)\s+amazon\s?pay\b',
      caseSensitive: false,
    ),
    PaymentProvider.bhim: RegExp(
      r'\b(via|using|through)\s+bhim\b',
      caseSensitive: false,
    ),
    PaymentProvider.cred: RegExp(
      r'\b(via|using|through)\s+cred\b',
      caseSensitive: false,
    ),
    PaymentProvider.whatsappPay: RegExp(
      r'\b(via|using|through)\s+whatsapp\s?pay\b',
      caseSensitive: false,
    ),
  };

  /// Weak hints only — a shared handle can genuinely belong to more than
  /// one app depending on which bank issued it, so this is a plausible
  /// guess, never trusted at the same strength as explicit phrasing.
  static const Map<String, PaymentProvider> _handleHints = {
    'ybl': PaymentProvider.phonePe,
    'ibl': PaymentProvider.phonePe,
    'okhdfcbank': PaymentProvider.googlePay,
    'oksbi': PaymentProvider.googlePay,
    'okicici': PaymentProvider.googlePay,
    'okaxis': PaymentProvider.googlePay,
    'paytm': PaymentProvider.paytm,
    'apl': PaymentProvider.amazonPay,
  };

  /// Returns `(provider, isExplicit)` — `isExplicit` distinguishes a
  /// message that names the app outright from a mere handle-based guess,
  /// mirroring the "known vs. inferred" distinction used elsewhere in this
  /// feature (see `TransactionStatusSignals.detectDetailed`).
  static ({PaymentProvider provider, bool isExplicit})? resolve({
    required String body,
    VpaInfo? vpa,
  }) {
    for (final entry in _explicitPhrasePatterns.entries) {
      if (entry.value.hasMatch(body))
        return (provider: entry.key, isExplicit: true);
    }
    final handle = vpa?.handle.toLowerCase();
    if (handle != null && _handleHints.containsKey(handle)) {
      return (provider: _handleHints[handle]!, isExplicit: false);
    }
    return null;
  }
}
