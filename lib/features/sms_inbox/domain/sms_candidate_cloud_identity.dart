import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bank_sender_matcher.dart';
import 'sms_transaction_direction.dart';

/// The Firestore document id for one SMS-derived transaction candidate —
/// deliberately a SEPARATE key from [SmsMessageKey] (exact per-row device
/// dedup) and `SmsDedupKey` (local duplicate-flagging heuristic). Those two
/// both hash `dateTime.millisecondsSinceEpoch` to exact-millisecond
/// precision, which is NOT safe as a cross-device cloud identity: that
/// timestamp is `content://sms`'s `date` column — the RECEIVING DEVICE'S OWN
/// local receive-time, not a value carried in the SMS itself (the PDU's
/// `date_sent` field is carrier-populated and commonly zero/unreliable). The
/// same physical SMS arriving on two devices under one account can log a
/// receive-time difference of whole seconds, which silently defeats an
/// exact-millisecond content hash — this was verified against the existing
/// code, not assumed.
///
/// EXPLICITLY VERSIONED (Phase F1 hardening, 2026-10-24). [compute] always
/// returns the CURRENT scheme's id — [forReferencedTransactionV2] — for a
/// NEW upload. [forReferencedTransactionV1] is kept, unchanged byte-for-byte
/// from the original Phase F1 formula, ONLY so callers can still compute a
/// legacy candidate's id to check an old tombstone or recognize an
/// already-uploaded legacy document — see `sms_candidate_cloud_sync.dart`'s
/// `_uploadUnlessHandled` for how both are actually used together. Nothing
/// in this file ever silently changes what an existing formula computes;
/// V1's formula is frozen forever, and a future V3 would be added the same
/// way, never by editing V1 or V2 in place.
///
/// V1 (frozen, 2026-10-24): normalizedSender | referenceNumber | amount |
/// direction. Known collision gap this version does NOT close: two
/// different accounts at the same bank, under the same user, could
/// (rarely) share a reference-number value on a same-amount transaction —
/// found during review, not hypothetical: [maskedAccountOrCard] was
/// already being parsed and already stored on the cloud document
/// (`rawLastFour`), but was never part of V1's identity.
///
/// V2 (current, 2026-10-24): normalizedSender | lastFour | referenceNumber
/// | amount | direction — adds the masked account/card last-4 digits,
/// narrowing the V1 gap above to "same bank AND same last-4," which is far
/// less likely to collide. See [forReferencedTransactionV2]'s own doc for
/// what "reliable" last-4 means and the conservative fallback when it
/// isn't available.
///
/// STRONG CASE — a bank reference/UPI transaction number is present:
/// hashes content, no timestamp at all. A bank-issued reference number
/// genuinely identifies one real transaction (banks do not reuse one across
/// two different transactions on the SAME account), so this is safe across
/// devices (the carrier delivers identical SMS text to every device) and
/// safe across time (no time-window collision risk) — the same eligible
/// message captured on two devices maps to the same candidate id, while two
/// distinct transactions that happen to share an amount and arrive minutes
/// apart stay distinct, because they carry different reference numbers.
///
/// CONSERVATIVE FALLBACK — no reference number could be parsed:
/// cross-device identity cannot be guaranteed safely from sender + amount +
/// body alone. A time-window fuzzy match (the pattern `SmsInboxDao
/// .findLikelyOriginalByFuzzyMatch` already uses for device-SMS-vs-RCS
/// matching) would wrongly collapse two genuinely separate, same-amount
/// purchases (e.g. two ₹150 coffees the same afternoon) into one candidate
/// if they land inside the window — exactly the case this feature's own
/// task explicitly warns against. Rather than accept that risk, or invent an
/// unsafe hash, [legacyPerDeviceId] is used instead: the existing per-device
/// `SmsInboxItem.id`. This means a message with no parseable reference
/// number does NOT get cross-device deduplication — captured identically on
/// two devices, it uploads as two candidates. That is a known, documented
/// limitation (a duplicate the user dismisses once), not a defect: the
/// alternative (an unsafe merge) risks silently losing a real transaction's
/// own candidate, which is strictly worse.
///
/// REMAINING COLLISION LIMITATION (V2, documented per task requirement, not
/// assumed away): last-4 digits are NOT globally unique, and
/// `SmsRegexUtils.extractMaskedAccount` does not distinguish an account
/// number from a card number — a message mentioning "a/c" vs "card" with
/// the same trailing 4 digits produces the same [maskedAccountOrCard] value
/// either way. A user with two accounts/cards at the same bank that happen
/// to share a last-4 digit AND a reference-number value AND an amount could
/// still theoretically collide under V2. This is accepted as a residual,
/// documented risk — closing it fully would require the real, unmasked
/// account number (never available here; this app only ever sees SMS text)
/// or a per-bank reference-number-format parser (out of scope, far larger
/// change). V2 is a real, measured improvement over V1, not a claim of
/// perfect uniqueness.
abstract class SmsCandidateCloudIdentity {
  SmsCandidateCloudIdentity._();

  /// Computes the CURRENT-scheme (V2) cloud document id for one local
  /// candidate, for use on every NEW upload. [sender] is the raw SMS
  /// sender/address (normalized internally); [referenceNumber] is whatever
  /// `SmsRegexUtils.extractReferenceNumber` parsed, if any;
  /// [maskedAccountOrCard] is whatever `SmsRegexUtils.extractMaskedAccount`
  /// parsed, if any; [legacyPerDeviceId] is the existing
  /// `SmsInboxItem.id`/`smsItemId`, reused verbatim as the conservative
  /// fallback — for the original no-reference-number case AND (as of the
  /// correction below) whenever [maskedAccountOrCard] is unavailable too —
  /// so every pre-existing cloud candidate in either of those states keeps
  /// its exact current document id: zero migration impact.
  ///
  /// SAFETY CORRECTION (2026-10-24): an EARLIER version of this method
  /// encoded a missing last-4 as the literal string `'none'` and still
  /// cross-device-merged on that basis. That was wrong: `'none'` carries no
  /// discriminating information, so two DIFFERENT accounts at the same
  /// bank, both happening not to expose a last-4 in their SMS text, with
  /// the same sender/reference/amount/direction, would have silently
  /// merged into one candidate — a false merge on weak evidence, exactly
  /// what this feature must never do. Per that correction, a missing or
  /// blank [maskedAccountOrCard] is now treated the SAME as a missing
  /// reference number: no cross-device merge is attempted at all, and
  /// [legacyPerDeviceId] is used instead. The trade-off is identical to the
  /// existing no-reference-number case: a message with a reference number
  /// but no last-4 does NOT get cross-device dedup — captured identically
  /// on two devices, it uploads as two candidates (a duplicate the user
  /// dismisses once) rather than risking a false merge.
  ///
  /// COMPATIBILITY: this correction was made before any version of the
  /// `'none'`-based formula ever shipped — background upload
  /// has stayed off throughout, and the foreground `sync()` path (the
  /// only live uploader) only ever ran against this still-uncommitted
  /// working tree. No deployed candidate or tombstone document was ever
  /// written under the old `'none'` formula, so no existing id is affected
  /// by this change — there is nothing to migrate or reconcile.
  static String compute({
    required String sender,
    required String? referenceNumber,
    required String? maskedAccountOrCard,
    required double amount,
    required SmsTransactionDirection direction,
    required String legacyPerDeviceId,
  }) {
    final hasReference =
        referenceNumber != null && referenceNumber.trim().isNotEmpty;
    final hasReliableLastFour =
        maskedAccountOrCard != null && maskedAccountOrCard.trim().isNotEmpty;
    if (!hasReference || !hasReliableLastFour) {
      return legacyPerDeviceId;
    }
    return forReferencedTransactionV2(
      sender: sender,
      referenceNumber: referenceNumber,
      maskedAccountOrCard: maskedAccountOrCard,
      amount: amount,
      direction: direction,
    );
  }

  /// FROZEN — the original Phase F1 formula, unchanged. Only ever called to
  /// check a LEGACY tombstone/candidate id, never for a new upload (see
  /// [compute]). Do not edit this method's hash input in place; a future
  /// version is added as a new method, the same way V2 was added alongside
  /// this one.
  static String forReferencedTransactionV1({
    required String sender,
    required String referenceNumber,
    required double amount,
    required SmsTransactionDirection direction,
  }) {
    final normalizedSender = BankSenderMatcher.normalize(sender);
    final raw =
        'ref|$normalizedSender|${referenceNumber.trim()}|${amount.toStringAsFixed(2)}|${direction.name}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// CURRENT — adds the masked account/card last-4 ([maskedAccountOrCard])
  /// to V1's inputs, closing the "same bank, different account, same
  /// reference-number value" gap V1 left open (see the class doc).
  ///
  /// REQUIRES a reliable (non-null, non-blank) [maskedAccountOrCard] —
  /// deliberately, not merely by convention. An earlier version of this
  /// method accepted a nullable last-4 and encoded its absence as the
  /// literal string `'none'`, still cross-device-merging on that basis.
  /// That was a real safety defect (caught 2026-10-24, before it ever
  /// shipped): `'none'` carries no discriminating information, so two
  /// DIFFERENT accounts at the same bank, both simply lacking a last-4 in
  /// their SMS text, with the same sender/reference/amount/direction,
  /// would have silently merged — a false merge on weak evidence. This
  /// method no longer accepts that case at all: [compute] is the only
  /// sanctioned caller, and it routes an unreliable last-4 to the
  /// conservative device-local fallback ([legacyPerDeviceId]) BEFORE ever
  /// reaching here — see [compute]'s own doc for the full rationale. A
  /// direct caller with a genuinely missing last-4 should not call this
  /// method at all.
  static String forReferencedTransactionV2({
    required String sender,
    required String referenceNumber,
    required String maskedAccountOrCard,
    required double amount,
    required SmsTransactionDirection direction,
  }) {
    final normalizedSender = BankSenderMatcher.normalize(sender);
    final raw =
        'ref2|$normalizedSender|${maskedAccountOrCard.trim()}|${referenceNumber.trim()}|${amount.toStringAsFixed(2)}|${direction.name}';
    return sha256.convert(utf8.encode(raw)).toString();
  }
}
