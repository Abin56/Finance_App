import '../merchant/merchant_key.dart';
import '../merchant/merchant_memory.dart';
import '../../../transactions/domain/transaction_type.dart';
import 'merchant_catalog.dart';
import 'merchant_evidence.dart';
import 'merchant_identity.dart';
import 'merchant_type.dart';
import 'upi_provider.dart';
import 'vpa_info.dart';

/// Resolves *who* a transaction's counterparty is, from deterministic
/// evidence only (no AI here — see `MerchantIntelligenceService` for where an
/// optional AI opinion is layered on top, and only when this resolver
/// abstains).
///
/// # Resolution order
///
/// 1. **VPA-shaped text** (either the parser's own merchant guess or the
///    first VPA found in the raw body): split into local part + handle
///    ([VpaParser]) and NEVER promoted to a display name — a VPA is
///    evidence, not an identity. Its normalized local part is still checked
///    against [MerchantIntelligenceCatalog] (`swiggy@upi` -> Swiggy), but a
///    miss stays `unknown`, never a guess from the local part itself (and
///    never, ever, from a phone-number-shaped local part into a person's
///    name — see [VpaInfo.localPartIsPhoneNumber]).
/// 2. **A payment-provider name mentioned as if it were the merchant**
///    (bare "PhonePe"/"Paytm"/... with nothing else) — recognized and kept
///    on [MerchantIdentity.paymentProvider], never treated as the merchant.
/// 3. **Known catalog match** on the normalized merchant text.
/// 4. **User transaction history** ([memories]) — if the user has
///    categorized this exact normalized merchant before, it's treated as
///    known-to-the-user (`isUserConfirmed`) even when the static catalog has
///    never heard of it (e.g. a local shop). The *category itself* isn't
///    resolved here (see `MerchantAwareCategoryResolver`) — only identity.
/// 5. **Individual-name heuristic** — a conservative, explicitly-labeled
///    guess (see [_looksLikeIndividualName]) that a bare, business-suffix-free
///    2-4-word capitalized name is a person, not a business. Never applied
///    to a VPA or phone number.
/// 6. Otherwise the explicit text is kept as an unrecognized business name
///    (never invented, never discarded) — or, with no text at all,
///    [MerchantIdentity.unknown].
class MerchantIdentityResolver {
  const MerchantIdentityResolver();

  static final RegExp _vpaShape = RegExp(r'^[\w.\-+]{2,}@[a-zA-Z]{2,}$');

  MerchantIdentity resolve({
    required String? regexMerchantGuess,
    required String smsBody,
    required List<MerchantMemory> memories,
    required TransactionType transactionType,
  }) {
    final providerFromText = UpiProviderResolver.fromMentionInText(smsBody);

    final guess = regexMerchantGuess?.trim();
    final isVpaGuess = guess != null && _vpaShape.hasMatch(guess);
    final vpa = isVpaGuess
        ? VpaParser.parse(guess)
        : VpaParser.findFirstInText(smsBody);

    if (isVpaGuess && vpa != null) {
      return _resolveFromVpa(vpa, providerFromText);
    }

    if (guess == null || guess.isEmpty) {
      // No merchant-shaped text at all; still surface a VPA found elsewhere
      // in the body (e.g. the sender's own account reference) as evidence,
      // but there is no candidate name to resolve identity from.
      if (vpa != null) return _resolveFromVpa(vpa, providerFromText);
      return const MerchantIdentity.unknown();
    }

    // A bare payment-provider name standing in for the merchant (e.g. a
    // regex fallback that grabbed "Paytm" from "via Paytm" with no payee) —
    // checked on the raw text, BEFORE `MerchantKey.normalize`, since several
    // provider names (`paytm`, `razorpay`) are themselves in that helper's
    // own noise-token list (stripped there for an unrelated reason — see
    // `MerchantKey`'s doc comment) and would otherwise normalize to `null`
    // and never reach the catalog-based check below at all.
    final guessLettersOnly = guess.toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    if (UpiProviderResolver.providerNameTokens.contains(guessLettersOnly)) {
      final provider = providerFromText != UpiProvider.unknown
          ? providerFromText
          : UpiProviderResolver.fromMentionInText(guess);
      return MerchantIdentity(
        merchantType: MerchantType.paymentProvider,
        isKnown: false,
        vpa: vpa,
        paymentProvider: provider == UpiProvider.unknown ? null : provider,
        evidence: MerchantEvidence(
          kind: MerchantEvidenceKind.regex,
          details: ['"$guess" names a payment provider/app, not a merchant'],
        ),
      );
    }

    final normalized = MerchantKey.normalize(guess);
    if (normalized == null) {
      return MerchantIdentity(
        merchantType: MerchantType.unknown,
        isKnown: false,
        vpa: vpa,
        paymentProvider: providerFromText == UpiProvider.unknown
            ? null
            : providerFromText,
        evidence: const MerchantEvidence.none(),
      );
    }

    // A catalog entry itself tagged as a payment provider (e.g. "Amazon
    // Pay") — different from the raw-text check above in that it's keyed by
    // the normalized string, for provider names that aren't noise-stripped.
    if (MerchantIntelligenceCatalog.isPaymentProviderName(normalized)) {
      final provider = providerFromText != UpiProvider.unknown
          ? providerFromText
          : UpiProviderResolver.fromMentionInText(guess);
      return MerchantIdentity(
        merchantType: MerchantType.paymentProvider,
        isKnown: false,
        vpa: vpa,
        paymentProvider: provider == UpiProvider.unknown ? null : provider,
        normalizedName: normalized,
        evidence: MerchantEvidence(
          kind: MerchantEvidenceKind.regex,
          details: ['"$guess" names a payment provider/app, not a merchant'],
        ),
      );
    }

    final catalogEntry = MerchantIntelligenceCatalog.lookup(normalized);
    if (catalogEntry != null) {
      return MerchantIdentity(
        displayName: catalogEntry.displayName,
        normalizedName: normalized,
        vpa: vpa,
        paymentProvider: providerFromText == UpiProvider.unknown
            ? null
            : providerFromText,
        merchantType: catalogEntry.merchantType,
        isKnown: true,
        categoryIsAmbiguous: catalogEntry.categoryIsAmbiguous,
        evidence: MerchantEvidence(
          kind: MerchantEvidenceKind.knownMerchantCatalog,
          details: [
            'normalized "$normalized" matched catalog entry "${catalogEntry.displayName}"',
          ],
        ),
      );
    }

    final userKnown = memories.any(
      (m) =>
          m.merchantKey == normalized && m.transactionType == transactionType,
    );
    if (userKnown) {
      return MerchantIdentity(
        displayName: guess,
        normalizedName: normalized,
        vpa: vpa,
        paymentProvider: providerFromText == UpiProvider.unknown
            ? null
            : providerFromText,
        merchantType: _looksLikeIndividualName(guess)
            ? MerchantType.individual
            : MerchantType.knownBusiness,
        isKnown: true,
        isUserConfirmed: true,
        evidence: MerchantEvidence(
          kind: MerchantEvidenceKind.userConfirmed,
          details: [
            'user has previously transacted with normalized merchant "$normalized"',
          ],
        ),
      );
    }

    if (_looksLikeIndividualName(guess)) {
      return MerchantIdentity(
        displayName: guess,
        normalizedName: normalized,
        vpa: vpa,
        paymentProvider: providerFromText == UpiProvider.unknown
            ? null
            : providerFromText,
        merchantType: MerchantType.individual,
        isKnown: false,
        evidence: MerchantEvidence(
          kind: MerchantEvidenceKind.regex,
          details: [
            '"$guess" reads as a person\'s name (heuristic, not confirmed)',
          ],
        ),
      );
    }

    // Explicit, unrecognized business text — kept verbatim, never discarded
    // and never promoted to "known".
    return MerchantIdentity(
      displayName: guess,
      normalizedName: normalized,
      vpa: vpa,
      paymentProvider: providerFromText == UpiProvider.unknown
          ? null
          : providerFromText,
      merchantType: MerchantType.unknownBusiness,
      isKnown: false,
      evidence: MerchantEvidence(
        kind: MerchantEvidenceKind.regex,
        details: [
          'explicit merchant text "$guess" not recognized by any known-merchant source',
        ],
      ),
    );
  }

  MerchantIdentity _resolveFromVpa(VpaInfo vpa, UpiProvider providerFromText) {
    final provider = providerFromText != UpiProvider.unknown
        ? providerFromText
        : vpa.provider;
    final normalizedLocal = MerchantKey.normalize(vpa.localPart);
    final catalogEntry = normalizedLocal == null
        ? null
        : MerchantIntelligenceCatalog.lookup(normalizedLocal);

    if (catalogEntry != null) {
      return MerchantIdentity(
        displayName: catalogEntry.displayName,
        normalizedName: normalizedLocal,
        vpa: vpa,
        paymentProvider: provider == UpiProvider.unknown ? null : provider,
        merchantType: catalogEntry.merchantType,
        isKnown: true,
        categoryIsAmbiguous: catalogEntry.categoryIsAmbiguous,
        evidence: MerchantEvidence(
          kind: MerchantEvidenceKind.knownMerchantCatalog,
          details: [
            'VPA local part "${vpa.localPart}" matched catalog entry "${catalogEntry.displayName}"',
          ],
        ),
      );
    }

    // No catalog match — the VPA itself is the only evidence. Deliberately
    // no displayName: a phone-number-shaped (or any other opaque) local part
    // must never be dressed up as a business or person name.
    return MerchantIdentity(
      normalizedName: normalizedLocal,
      vpa: vpa,
      paymentProvider: provider == UpiProvider.unknown ? null : provider,
      merchantType: MerchantType.unknown,
      isKnown: false,
      evidence: MerchantEvidence(
        kind: vpa.localPartIsPhoneNumber
            ? MerchantEvidenceKind.none
            : MerchantEvidenceKind.regex,
        details: vpa.localPartIsPhoneNumber
            ? [
                'VPA local part looks like a phone number — never inferring an identity from it',
              ]
            : ['VPA "${vpa.raw}" has no known-merchant match; kept as unknown'],
      ),
    );
  }

  /// A deliberately conservative, explicitly-labeled-as-heuristic guess that
  /// [text] names a person rather than a business: 2-4 space-separated
  /// words, each starting with an uppercase letter, no digits anywhere, and
  /// none of a short list of business-suffix words. False negatives (a
  /// business name that happens to look like this) are the safe failure
  /// mode — [MerchantType.individual] never suppresses a real category
  /// suggestion the way "unknown" would, it only affects the *label* shown.
  static final RegExp _businessSuffixWords = RegExp(
    r'\b(store|stores|mart|shop|traders|enterprises|restaurant|cafe|bakery|'
    r'ltd|pvt|inc|llp|services|solutions|technologies|technology|industries|'
    r'agency|agencies|hospital|clinic|pharmacy|electronics|textiles|bank|'
    r'academy|school|college|university|hotel|motel|resort)\b',
    caseSensitive: false,
  );

  static bool _looksLikeIndividualName(String text) {
    if (RegExp(r'\d').hasMatch(text)) return false;
    if (_businessSuffixWords.hasMatch(text)) return false;
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.length < 2 || words.length > 4) return false;
    return words.every((w) => RegExp(r'^[A-Z][a-zA-Z\.]*$').hasMatch(w));
  }
}
