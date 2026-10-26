# SMS Auto Sync (background capture)

Opt-in, **sideload flavor only**. Captures bank SMS / Google Messages (RCS)
alerts without the app being open and stores them in the existing local
`sms_inbox` store for review. **It does not upload anything to Firestore unless the runtime switch below is enabled** —
see "Background cloud upload: runtime switch".

## Flow

```
SMS_RECEIVED ──► SmsReceiver ──┐   (text inspected in memory, never stored)
RCS notification ► NotificationCaptureListenerService ──┤ (existing capture store)
                               ▼
        AutoSyncPrefs.recordSignal + SmsScanScheduler.enqueue
                               ▼
   WorkManager unique chain "flowfi_sms_auto_scan" (5 s delay, exp. backoff)
                               ▼
   SmsScanWorker ─► headless FlutterEngine ─► smsBackgroundMain()
                               ▼
   SmsInboxRepository.scanInbox()  (same filter, bank parsers, dedup as manual scan)
                               ▼
             local sqflite `sms_inbox`  (status = pending)
```

- The receiver is a *trigger only*: multipart SMS are joined in memory, run
  through `SmsFinancialPrefilter` (OTP/login/security → rejected;
  promo/reminder without a transaction verb → rejected), then discarded. Only
  a counter is persisted (`AutoSyncPrefs`).
- The durable event store is the existing `sms_inbox` table (UNIQUE
  `message_key`), so no second database exists. Re-runs, retries, concurrent
  workers and a later manual scan all collapse to the same row.
- WorkManager provides persistence across process death/reboot, a single
  unique chain (no concurrent workers; `APPEND_OR_REPLACE` so a message
  arriving mid-scan gets a follow-up scan), and exponential backoff
  (30 s base, 6 attempts). Permission loss is not retried; it is surfaced.
- States: Pending = signal counted/`sms_inbox` row `pending`; Processing =
  worker running; Retry = backoff after failure; Rejected = prefilter counter.
  Synced does not exist yet (no upload).

## RCS (best-effort)

Only works while Notification Access is granted and Google Messages actually
posts a notification. The package check now accepts Google Messages by name
(`com.google.android.apps.messaging`, Samsung/AOSP SMS apps) in addition to
`getDefaultSmsPackage()`, which could be `null` and previously rejected every
notification. A missing `EXTRA_TITLE` no longer drops the alert. Unrelated apps
are rejected before any content is read. No history is available — only
notifications posted after access is granted. Notification dedup uses SHA-256
(was a 32-bit `hashCode`).

Personal-chat guard: notification-sourced text must also carry bank/UPI evidence
(account/card digits, VPA, reference number, or balance line) —
`NotificationBankEvidence` (Dart, enforced in `scanInbox` for notification
rows only) mirrored by `SmsFinancialPrefilter.hasBankEvidence` (Kotlin, in the
listener). Without it, a friend's RCS "I paid Rs 500 for lunch" was parsed into
a candidate. Wallet alerts lacking all such evidence are skipped (best-effort).
RCS ingestion also needs SMS permission: `scanInbox()` reads the SMS provider
first and aborts on `permission_denied`, so Auto Sync (which requires it) is
the supported way to ingest captured RCS rows in the background.

Known limit: an RCS notification's title is a display name ("HDFC Bank"), while
the SMS sender is a DLT id ("VM-HDFCBK"); the existing fuzzy dedup compares
normalized senders, so the same alert arriving by both channels can show as two
items. Pre-existing; not changed here.

## Not guaranteed

Force-stop, revoked SMS permission, revoked Notification Access, RCS
notifications disabled, and OEM battery restrictions stop capture. No
foreground service is used.

## Background cloud upload: runtime switch (Phase F3, 2026-10-25)

**Default OFF for every account and device.** There is no hard-coded "on". The
headless worker uploads only when ALL of these are true, read fresh from the
Firestore SERVER on every background scan:

- someone is signed in (uid resolved in the headless isolate);
- `users/{uid}/smsSyncConfig/backgroundUpload` exists;
- its `enabled` is boolean `true`;
- its `deviceId` equals this install's **Sync device ID** (random per-install
  UUID, shown in the SMS Auto Sync card; not a hardware id).

Anything else (no doc, `enabled:false`, other device, wrong types, offline,
timeout, permission denied, Firebase/Auth not available, unreadable id) means
**no upload** (fail closed; no cached last-known-good). The document is under
the user's own path, so it cannot authorize another account, and `deviceId`
keeps a second phone on the same account OFF. Clients cannot write it
(`firestore.rules`: `allow write: if false`); only the console / Admin SDK can.

Nothing here logs SMS content, uid, or the device id. Upload still goes through
`SmsCandidateCloudSync` (UID isolation via `capturedForUid`, V1/V2 identity and
tombstone checks unchanged) and never creates financial transactions.

### Required Firestore rules change (NOT deployed by this work)

Added identically to `Flow-Fi-WEB/firestore.rules` and
`Finance_App/firestore.rules` (they must stay byte-identical):

```
match /users/{uid}/smsSyncConfig/{configId} {
  allow read: if isOwner(uid);
  allow write: if false;
}
```

Until this is deployed, the worker's read is denied, so upload stays OFF
(fail closed). Covered by `tests/rules/firestore.rules.test.ts`
(`npm run test:rules`).

### Activation by QR pairing (2026-10-25 — the customer path)

Users no longer need any of the manual steps below. FlowFi Web's Transaction
Inbox shows a single-use pairing QR; the app's `/pair` screen
(`lib/features/sms_inbox/pairing/`) verifies it for the signed-in account,
asks for explicit approval, and the pairing Cloud Functions (Flow-Fi-WEB
`functions/src/sms-pairing/`) then register this install in
`users/{uid}/smsDevices` and write `backgroundUpload` for it. The phone then
reports its setup/health to `users/{uid}/smsDeviceStatus/{deviceId}` so the web
can follow along. Operator emergency switches (`smsSyncControl/global`,
`users/{uid}/smsSyncConfig/operatorHold`) are read by
`SmsBackgroundUploadSwitch` and enforced by firestore.rules; pairing can't clear
them. Full design, deployment and test plan: Flow-Fi-WEB
`docs/sms-sync-pairing.md`. The manual procedure below still works for
operator-only activation.

### Manual activation (one account, one device)

1. Deploy the rules above (operator step).
2. Install the build on the phone, sign in as the authorized account, open SMS
   Inbox → SMS Auto Sync card, and copy **Sync device ID**.
3. Firebase console → Firestore → `users/<AUTHORIZED_UID>/smsSyncConfig`, add
   document id `backgroundUpload` with fields `enabled` (boolean) = `true` and
   `deviceId` (string) = the copied id.
4. Trigger/wait for a background scan. Candidates appear in
   `users/<uid>/smsTransactionCandidates` and on the web Transaction Inbox.

### Disable (no rebuild)

Set `enabled` to `false`, or delete the `backgroundUpload` document. Takes
effect on the next background scan. Candidates already uploaded stay until
imported/dismissed. Clearing app data or reinstalling creates a new Sync device
ID, which is OFF until the document is updated.

## Sync health diagnostics (Phase F4, 2026-10-25)

The SMS Auto Sync card separates the **local scan** from **cloud upload**:

| Row | Meaning |
|---|---|
| Last scan attempt / Last successful scan | Local scan only, independent of upload |
| Cloud Sync: Off | Switch read OK, does not authorize this account/device (default) |
| Cloud Sync: On | Switch authorizes this account + device |
| Cloud Sync: Can't verify | Switch could not be read (offline, signed out, permission denied, timeout). Nothing is uploaded (fail closed) |
| Cloud Sync: Not checked yet | No run has reported since install/update |
| Last cloud upload | Shown only when On; failure note, and "failed N times in a row" after 5 |

Stored **locally only** in SharedPreferences (`sms_sync_diag_*` keys): the
headless worker writes one attempt marker and one outcome update per run, with
no Firestore writes. Only timestamps, counters and category codes
(`auth_unavailable`, `permission_denied`, `offline`, `timeout`, `unknown`) are
kept; never SMS body/sender, uid, device id, account/card details, or exception
text. The Web app has no device-status source (see `sms-sync-onboarding.tsx` in
Flow-Fi-WEB) and makes no connected/syncing claim.

## Why cloud upload was off by default (history)

Historical (before F3, a hard-coded `kSmsAutoSyncCloudUploadEnabled = false`; now replaced by the runtime switch above). Reason: the Web app deletes a
candidate document when it imports or dismisses it, and the contract has no
status field. A background upload cannot distinguish "never synced" from
"already handled", so it would resurrect handled candidates (the Web only
warns "Possible Duplicate"). Existing foreground sync
(`SmsInboxItemsNotifier.scan` → `SmsCandidateCloudSync`) is unchanged.

### Handled-candidate tombstone proposal (needs approval — nothing implemented)

Smallest change that lets Android recognise handled items:

1. Web, instead of `deleteDoc` on import/dismiss, writes
   `users/{uid}/smsCandidateTombstones/{smsItemId}` =
   `{ handledAt: Timestamp, outcome: "imported" | "dismissed" }` (still deleting
   the candidate doc). Alternative: keep the candidate doc and set a
   `status` field, but that changes the "existence = pending" contract and the
   Web listener filter.
2. Android upload (background or foreground) reads the tombstone id set and
   skips / deletes-local those ids; `SmsCandidateCloudSync.sync` would also mark
   the local item ignored/imported.
3. Firestore rules: tombstones are owner read/write (same `isOwner(uid)` rule
   shape); no rules change needed if placed under an already-matched path, but a
   new collection needs a one-line match.
4. Web idempotency (`evaluateCandidateDuplicate`) stays as the second guard.

Requires: Firebase schema change, Web change, rules line. None applied.

Also needed before enabling any upload: bind the worker to the signed-in uid
(re-read `FirebaseAuth.currentUser` at upload time, abort if it differs from
the uid recorded when the item was captured) — the local `sms_inbox` store is
device-wide and not partitioned per user.

## Privacy

No raw text is logged or uploaded by the new code; worker→UI errors are short
codes. Raw bodies still live in the existing on-device `sms_inbox` (unchanged)
and the RCS capture store (500-row cap, unchanged).

## Device verification (not run — needs a physical Android device)

```
adb install -r build/app/outputs/flutter-apk/app-sideload-debug.apk
adb shell pm grant com.flowfi.app android.permission.RECEIVE_SMS
adb shell pm grant com.flowfi.app android.permission.READ_SMS
# enable "SMS Auto Sync" in the SMS Inbox, then swipe the app away from Recents
# (do NOT use `am force-stop` or Settings > Force stop: that stops all capture
# until the app is opened again — expected Android behaviour)
# emulator only: send a test SMS
adb emu sms send VM-HDFCBK "Rs.1,250.00 debited from a/c XX5623 on 20-10-26 to VPA swiggy@icici. Ref No 123456789012."
adb shell dumpsys jobscheduler | findstr flowfi        # work scheduled
adb logcat -s FinanceAppNotifCap WM-WorkerWrapper      # no message text expected
# reboot while work is queued, confirm it still runs
adb reboot
# RCS: grant Notification Access, receive a real Google Messages bank alert,
# confirm `getCaptured` row appears and a scan is enqueued
adb shell cmd notification allow_listener com.flowfi.app/.NotificationCaptureListenerService
```
Revocation check: `adb shell pm revoke com.flowfi.app android.permission.RECEIVE_SMS`
then confirm the card shows "SMS permission removed".
