import 'upi_provider.dart';

/// A parsed UPI VPA (`local@handle`), kept as its own value object because a
/// VPA is *evidence*, not an identity — see [VpaParser]'s class doc for the
/// hallucination rule this exists to enforce.
class VpaInfo {
  const VpaInfo({
    required this.raw,
    required this.localPart,
    required this.handle,
    required this.provider,
    required this.localPartIsPhoneNumber,
  });

  /// The full, untouched VPA exactly as it appeared in the message.
  final String raw;

  /// The part before `@` — may be a business slug (`swiggy`), a phone
  /// number, or an opaque merchant code. Never itself treated as a
  /// human-readable name.
  final String localPart;

  /// The part after `@` (without the `@`), e.g. `oksbi`, `ybl`, `paytm`.
  final String handle;

  final UpiProvider provider;

  /// True when [localPart] is a bare 10-digit (optionally +91-prefixed)
  /// number — the strongest signal that this VPA is a personal, not
  /// business, account, and specifically the case [VpaParser] exists to
  /// protect: this must never be turned into a person's name.
  final bool localPartIsPhoneNumber;

  @override
  String toString() => raw;
}

/// Parses a UPI VPA into its evidentiary parts. Deliberately does *nothing*
/// more than that — no attempt to look up who a phone-number-shaped VPA
/// belongs to, no inference of a business name from an opaque local part.
/// See the "no hallucination" rule this whole merchant-intelligence layer is
/// built around: a VPA reveals its own shape, never a real-world identity by
/// itself.
abstract class VpaParser {
  VpaParser._();

  static final RegExp _vpaPattern = RegExp(r'^([\w.\-+]{2,})@([a-zA-Z]{2,})$');
  static final RegExp _phoneNumberPattern = RegExp(r'^(\+?91)?[6-9]\d{9}$');

  /// Returns `null` when [raw] isn't VPA-shaped at all.
  static VpaInfo? parse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final match = _vpaPattern.firstMatch(trimmed);
    if (match == null) return null;
    final localPart = match.group(1)!;
    final handle = match.group(2)!;
    return VpaInfo(
      raw: trimmed,
      localPart: localPart,
      handle: handle,
      provider: UpiProviderResolver.fromHandle(handle),
      localPartIsPhoneNumber: _phoneNumberPattern.hasMatch(localPart),
    );
  }

  /// Scans free-form text for the first VPA-shaped token, then delegates to
  /// [parse]. Mirrors `SmsRegexUtils`'s own VPA regex shape so results agree
  /// with what the rest of the pipeline already extracted.
  static VpaInfo? findFirstInText(String body) {
    final match = RegExp(r'\b([\w.\-]{2,}@[a-zA-Z]{2,})\b').firstMatch(body);
    if (match == null) return null;
    return parse(match.group(1));
  }
}
