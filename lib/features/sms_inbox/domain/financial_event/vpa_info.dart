/// A parsed UPI VPA (`someone@bank`) — kept as structured **evidence**, never
/// a guaranteed identity. `merchant@ybl` tells you a lot less than a real
/// name does: [localPart] might be a business's chosen handle ("swiggy"),
/// a person's initials, or a random alphanumeric string a payment app
/// generated — [VpaParser] only ever exposes the raw pieces, and it is
/// explicitly `MerchantIdentityResolver`'s job (not this class's) to decide
/// whether [localPart] is trustworthy enough to become a display name.
class VpaInfo {
  const VpaInfo({
    required this.raw,
    required this.localPart,
    required this.handle,
  });

  /// The full VPA exactly as it appeared in the message.
  final String raw;

  /// The part before `@` — e.g. `swiggy` in `swiggy@upi`. Never itself
  /// treated as a person's name or a merchant name without corroborating
  /// evidence (a catalog match, or explicit SMS text elsewhere).
  final String localPart;

  /// The part after `@` — e.g. `upi`, `oksbi`, `ybl`, `paytm`. Identifies
  /// the PSP/bank handle, not the counterparty.
  final String handle;
}

/// Parses a raw VPA string into its structured pieces. Deliberately narrow —
/// this only splits `local@handle`, it never attempts to resolve identity
/// (see [MerchantIdentityResolver] for that).
abstract class VpaParser {
  VpaParser._();

  static final RegExp _vpaPattern = RegExp(
    r'^([\w.\-]{2,})@([a-zA-Z][\w.\-]{1,})$',
  );

  /// Returns null when [raw] isn't VPA-shaped at all — never a partial or
  /// guessed parse.
  static VpaInfo? parse(String raw) {
    final trimmed = raw.trim();
    final match = _vpaPattern.firstMatch(trimmed);
    if (match == null) return null;
    return VpaInfo(
      raw: trimmed,
      localPart: match.group(1)!,
      handle: match.group(2)!,
    );
  }
}
