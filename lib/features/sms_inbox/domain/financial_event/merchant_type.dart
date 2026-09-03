/// Whether a resolved counterparty is a registered business or an
/// individual person (a P2P transfer) — kept separate from
/// [MerchantSource]/confidence, since "who is this" and "how sure am I"
/// are independent questions. `unknown` is the honest default whenever
/// there isn't enough evidence to tell, never guessed from a bare VPA or
/// account-shaped token.
enum MerchantType { business, person, unknown }

extension MerchantTypeX on MerchantType {
  static MerchantType fromName(String? name) {
    if (name == null) return MerchantType.unknown;
    return MerchantType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => MerchantType.unknown,
    );
  }
}
