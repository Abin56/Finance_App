import '../merchant/merchant_key.dart';
import 'merchant_identity.dart';

/// A small, per-scan in-memory cache of resolved [MerchantIdentity]s, keyed
/// by VPA (when present) or normalized merchant text. A single SMS scan can
/// contain dozens of messages from the same merchant (a week of Swiggy
/// orders, a month of the same EMI) — without this, each one would repeat
/// the same catalog lookup (cheap) or, worse, the same AI call (not cheap,
/// and pure waste once the first call already answered the question) — see
/// `AiCallNecessity`.
///
/// Deliberately unbounded and un-evicted: one scan processes at most the
/// device's SMS inbox (capped at 500 by `SmsReaderAdapter`), so the realistic
/// upper bound on distinct merchants is small enough that a plain `Map`
/// never becomes a real memory concern. A fresh instance is created per
/// scan (see the pipeline wiring in `sms_inbox_providers.dart`) — this is
/// not a persistent, cross-scan cache.
class MerchantIdentityCache {
  MerchantIdentityCache();

  final Map<String, MerchantIdentity> _store = {};

  String? _keyFor({String? vpaRaw, String? merchantText}) {
    if (vpaRaw != null && vpaRaw.trim().isNotEmpty)
      return 'vpa:${vpaRaw.trim().toLowerCase()}';
    final normalized = MerchantKey.normalize(merchantText);
    return normalized == null ? null : 'text:$normalized';
  }

  MerchantIdentity? get({String? vpaRaw, String? merchantText}) {
    final key = _keyFor(vpaRaw: vpaRaw, merchantText: merchantText);
    if (key == null) return null;
    return _store[key];
  }

  void put(MerchantIdentity identity, {String? vpaRaw, String? merchantText}) {
    final key = _keyFor(vpaRaw: vpaRaw, merchantText: merchantText);
    if (key == null) return;
    _store[key] = identity;
  }
}
