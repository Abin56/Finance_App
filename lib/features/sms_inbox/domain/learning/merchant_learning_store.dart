import 'merchant_learning_profile.dart';
import 'merchant_provider_guard.dart';

/// In-memory reference store for `MerchantLearningProfile`s, keyed by user +
/// merchant. This is intentionally not backed by `sms_inbox.db` yet — wiring
/// persistence in is a real, separate integration decision (a new table,
/// migration, and DAO mirroring `MerchantMemoryDao`) left to whoever adopts
/// this layer, so it isn't made silently here. See this module's "known
/// limitations" notes.
class MerchantLearningStore {
  MerchantLearningStore() : _profiles = {};

  final Map<String, MerchantLearningProfile> _profiles;

  String _key(String userId, String merchantKey) => '$userId::$merchantKey';

  MerchantLearningProfile? get(String userId, String merchantKey) =>
      _profiles[_key(userId, merchantKey)];

  List<MerchantLearningProfile> allForUser(String userId) => _profiles.values
      .where((profile) => profile.userId == userId)
      .toList(growable: false);

  /// Throws [ArgumentError] rather than silently dropping or renaming the
  /// key when [profile.merchantKey] is actually a payment provider — see
  /// `MerchantProviderGuard`. Surfacing this loudly at the write boundary is
  /// deliberate: a provider slipping in here means a bug upstream picked the
  /// wrong string as the merchant, and masking it would only hide that bug.
  void put(MerchantLearningProfile profile) {
    if (MerchantProviderGuard.isProviderName(profile.merchantKey)) {
      throw ArgumentError.value(
        profile.merchantKey,
        'merchantKey',
        'is a payment provider, not a merchant — see MerchantProviderGuard',
      );
    }
    _profiles[_key(profile.userId, profile.merchantKey)] = profile;
  }
}
