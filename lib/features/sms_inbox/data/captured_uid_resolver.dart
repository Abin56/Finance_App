import 'package:firebase_auth/firebase_auth.dart';

/// Resolves "whoever is signed in right now, if anyone" — the single seam
/// both [SmsInboxRepository.scanInbox] (binds a newly captured row to this
/// uid) and `SmsCandidateCloudSync.sync` (requires a local row's bound uid
/// to match this uid before uploading it) go through, so both halves of the
/// SMS Auto Sync ownership story read the same signal the same way.
///
/// A plain synchronous `String? Function()` rather than a Riverpod provider
/// or anything `async`/stream-based: this must work identically from a
/// normal widget-tree context AND from the headless background entrypoint
/// (`sms_background_entry.dart`), which has no provider scope and — per
/// `Finance_App/docs/sms-background-cloud-sync-architecture.md`'s Unresolved
/// Decisions §2 — may not even have `Firebase.initializeApp()` called yet in
/// that process. See [defaultCapturedUidResolver] for how that's handled.
typedef CapturedUidResolver = String? Function();

/// The real implementation: the current `FirebaseAuth` user's uid, or `null`
/// if nobody is signed in — or if Firebase Auth itself isn't available at
/// all in this isolate, which `FirebaseAuth.instance` throws for rather than
/// returning null.
///
/// SMS capture must never depend on Firebase Auth being available (Phase C
/// requirement: "Do not make Firebase Auth a requirement for local SMS
/// capture"). The headless background isolate started by `SmsScanWorker`
/// never calls `Firebase.initializeApp()` today — accessing
/// `FirebaseAuth.instance` there throws a `[core/no-app]`-style error, not a
/// null user. Catching that and returning `null` is what keeps background
/// capture working exactly as before: the row is simply captured as
/// "unowned" (`capturedForUid: null`), never silently dropped, and never
/// bound to a guessed uid.
String? defaultCapturedUidResolver() {
  try {
    return FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    return null;
  }
}

/// Resolves the CURRENT sign-in session's start time — the other half of
/// the Phase D ownership safeguard alongside [defaultCapturedUidResolver].
///
/// PRECHECK FINDING (Phase D, 2026-10-24): binding `captured_for_uid` purely
/// to "whoever is signed in at the moment this row is first scanned" has a
/// real gap. The physical SMS provider can hold a message for a long time
/// before it is ever scanned (Auto Sync was off, the device was offline, the
/// app simply wasn't opened). If that message arrived while User A was
/// signed in, but the FIRST scan that ever discovers it runs only after User
/// A signed out and User B signed in, the old code bound it to B — a real
/// cross-account misattribution, not merely a timing curiosity.
///
/// The smallest safe fix: a message is only eligible to be bound to the
/// current uid if it was received AT OR AFTER that uid's current sign-in
/// session started (`User.metadata.lastSignInTime`, which `firebase_auth`
/// already tracks — no new persisted state needed). A message that predates
/// the current session is left unowned (`null`), exactly like a message
/// scanned while nobody is signed in — conservative by design: it is better
/// to leave a genuinely-A message unowned forever than to risk uploading it
/// under B. See [SmsInboxRepository.scanInbox]'s use of this alongside
/// [CapturedUidResolver].
///
/// Known conservative trade-off, stated plainly rather than hidden: if the
/// SAME user signs out and back in, `lastSignInTime` advances to the new
/// sign-in moment, so a message that arrived during that same user's
/// EARLIER session (before this latest re-sign-in) and still hasn't been
/// scanned also becomes ineligible — not a safety problem (nothing crosses
/// accounts), just a message that stays unowned a little longer than
/// strictly necessary. Fixing that would require persisting every past
/// sign-in's own window, which is a materially bigger change than this
/// precheck calls for.
typedef CapturedUidSignInTimeResolver = DateTime? Function();

/// `null` means either nobody is signed in, or the current user's
/// `lastSignInTime` isn't available — both treated identically by
/// [SmsInboxRepository.scanInbox]: no message is eligible for binding
/// without a known, trustworthy session start time.
DateTime? defaultCapturedUidSignInTimeResolver() {
  try {
    return FirebaseAuth.instance.currentUser?.metadata.lastSignInTime;
  } catch (_) {
    return null;
  }
}
