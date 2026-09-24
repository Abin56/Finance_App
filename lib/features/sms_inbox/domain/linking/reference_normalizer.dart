/// Normalizes an already-extracted reference/UTR/transaction-id string
/// (`FinancialEvent.referenceNumber`) for comparison — Part 4 of the task.
///
/// This does NOT re-extract a reference number from raw SMS text (that
/// stays the extractor's job, an owned file this phase does not touch); it
/// only makes two already-extracted values comparable regardless of
/// incidental formatting differences (case, stray spaces/dashes) that can
/// legitimately vary between two SMS describing the same UPI Ref/Txn ID —
/// e.g. "123456789012" vs "123456789012" with different surrounding label
/// text ("UPI Ref" vs "Ref No") already collapses to the same extracted
/// value upstream, but this guards the comparison itself against
/// formatting noise the extractor might still leave in (a trailing dot, an
/// inconsistent case on an alphanumeric UTR).
abstract class ReferenceNormalizer {
  ReferenceNormalizer._();

  static final _nonAlphanumeric = RegExp(r'[^A-Za-z0-9]');

  /// `null` if [raw] is `null`, empty, or normalizes to nothing.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final stripped = raw.replaceAll(_nonAlphanumeric, '').toUpperCase();
    return stripped.isEmpty ? null : stripped;
  }

  /// True only when both normalize to the same non-empty value — two
  /// `null`/unresolved reference numbers are never considered a match
  /// (Safety rule: "different reference IDs must not be merged" implies
  /// the absence of one is not itself a signal).
  static bool matches(String? a, String? b) {
    final na = normalize(a);
    final nb = normalize(b);
    return na != null && nb != null && na == nb;
  }
}
