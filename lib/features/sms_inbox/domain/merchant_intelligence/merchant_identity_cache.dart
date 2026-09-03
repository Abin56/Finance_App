import 'merchant_identity.dart';

/// A tiny in-memory cache so repeated resolution of the same normalized
/// merchant/VPA key doesn't repeatedly re-run keyword scans or (were one
/// wired in) re-call an AI provider. Deliberately not persisted anywhere —
/// this is a session-scoped speed/cost optimization, not a data store; the
/// durable "remember what the user chose" job belongs to `MerchantMemory`
/// (via `MerchantMemoryRepository`), which this cache does not replace.
///
/// Correction handling: this cache has no way to observe
/// `MerchantMemoryRepository.record` calls without modifying that existing
/// file (out of scope for this module — see the parallel-development
/// notes), so callers that record a user correction for a given normalized
/// key MUST call [invalidate] with that same key immediately afterward.
/// [MerchantIntelligenceService.resolve] documents this pairing at its call
/// site.
class MerchantIdentityCache {
  final Map<String, MerchantIdentity> _byKey = {};

  MerchantIdentity? get(String normalizedKey) => _byKey[normalizedKey];

  void put(String normalizedKey, MerchantIdentity identity) {
    _byKey[normalizedKey] = identity;
  }

  /// Must be called whenever a user correction is recorded for
  /// [normalizedKey] (e.g. right after
  /// `MerchantMemoryRepository.record(...)`) so a stale, pre-correction
  /// identity/category is never served again for this key.
  void invalidate(String normalizedKey) {
    _byKey.remove(normalizedKey);
  }

  void clear() => _byKey.clear();

  int get length => _byKey.length;
}
