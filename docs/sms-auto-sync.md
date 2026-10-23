# SMS Auto Sync (background capture)

Opt-in, **sideload flavor only**. Captures bank SMS / Google Messages (RCS)
alerts without the app being open and stores them in the existing local
`sms_inbox` store for review. **It does not upload anything to Firestore** —
see "Cloud upload is intentionally off".

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

## Cloud upload is intentionally off

`kSmsAutoSyncCloudUploadEnabled = false`. Reason: the Web app deletes a
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
adb shell pm grant com.example.finance_app android.permission.RECEIVE_SMS
adb shell pm grant com.example.finance_app android.permission.READ_SMS
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
adb shell cmd notification allow_listener com.example.finance_app/.NotificationCaptureListenerService
```
Revocation check: `adb shell pm revoke com.example.finance_app android.permission.RECEIVE_SMS`
then confirm the card shows "SMS permission removed".
