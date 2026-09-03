/// Verifies that an AI-claimed "evidence" quote genuinely occurs in the SMS
/// it was supposedly quoted from — the second half of the "never invent
/// data" principle. A non-empty `evidence` string alone (the only check
/// `MerchantResolver`/`MerchantIdentityResolver` used to make) is not proof
/// the AI actually read it there rather than inventing a plausible-sounding
/// quote; this closes that gap with a cheap, fully local, on-device check
/// that runs against the real message text — nothing new is sent
/// off-device, and the existing redaction policy (`SmsBodyRedactor`) is
/// untouched.
///
/// Deliberately a plain substring check, not fuzzy matching: fuzzy
/// similarity is exactly the kind of check invented text can slip through.
/// The only slack given is safe, meaning-preserving normalization (case,
/// whitespace, a small set of punctuation marks) — never anything that
/// could make two genuinely different phrases compare equal.
abstract class EvidenceGrounding {
  EvidenceGrounding._();

  /// Punctuation safe to drop entirely before comparing — marks that a human
  /// (or a model) might add/omit around a quote without changing its
  /// meaning. Deliberately excludes anything that carries real information
  /// in this domain: '@' (VPA separator), digits, '-', and '&' are never
  /// touched, since collapsing those could make two different VPAs or
  /// amounts compare equal.
  static final RegExp _safePunctuation = RegExp('[.,;:!?\'"()\\[\\]]');

  static final RegExp _whitespace = RegExp(r'\s+');

  /// True when [evidence] (after safe normalization) occurs verbatim inside
  /// [body] (after the same normalization). `false` for a null/blank
  /// [evidence] — an empty claim is never "grounded", it's simply absent,
  /// which callers should treat as "the AI had no opinion" same as before.
  static bool isGrounded({required String? evidence, required String body}) {
    if (evidence == null) return false;
    final normalizedEvidence = normalize(evidence);
    if (normalizedEvidence.isEmpty) return false;
    final normalizedBody = normalize(body);
    return normalizedBody.contains(normalizedEvidence);
  }

  /// Lowercases, strips a small safe punctuation set, and collapses
  /// whitespace runs to a single space. Exposed (not just used internally)
  /// so callers that need to reason about *why* grounding failed can
  /// normalize both sides the same way for a diff/log message.
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(_safePunctuation, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
  }
}
