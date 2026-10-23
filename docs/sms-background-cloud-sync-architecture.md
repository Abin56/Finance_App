# SMS Background Cloud Sync — Architecture Proposal (needs approval, nothing implemented)

Status: **proposal only**. Supersedes/completes the "Handled-candidate tombstone
proposal" stub in `sms-auto-sync.md`. No code has been written for this yet;
`kSmsAutoSyncCloudUploadEnabled` stays `false` until Phase D below is explicitly
approved and merged.

Builds on the confirmed root-cause audit (2026-10-23): background scan never
calls Firestore at all; the headless isolate never calls `Firebase.initializeApp()`;
the local dedup key (`sms_dedup_key.dart`) only prevents re-importing the same SMS
*locally* and has no bearing on Web-side handled-state.

---

## 1. Tombstone / handled-state design

**Path:** `users/{uid}/smsCandidateTombstones/{smsItemId}` — **same document id**
as the candidate it replaces (`SmsInboxItem.id`, the id `smsTransactionCandidates`
already uses). 1:1 by construction; no separate id scheme needed, and a single
`getDoc`/transactional read by candidate id is enough to check handled-state.

**Fields:**

| Field | Type | Notes |
|---|---|---|
| `handledAt` | `Timestamp` (server time) | |
| `outcome` | `"imported" \| "dismissed"` | |
| `transactionId` | `string \| null` | set only for `"imported"`; diagnostic, not load-bearing |
| `source` | `"web"` literal | future-proofs if Android ever writes its own tombstones |
| `schemaVersion` | `number`, starts at `1` | |

**Lifecycle:**
- **Import:** the existing "delete candidate doc" step in `import-candidate.ts`
  (success path, and the `already_imported` settle path) becomes one atomic
  `WriteBatch`: delete `smsTransactionCandidates/{id}` + `set` the tombstone
  (`outcome: "imported"`, `transactionId`).
- **Dismiss:** `ignoreCandidate()` becomes the same atomic batch with
  `outcome: "dismissed"`, `transactionId: null`.
- **Undo:** no change needed. `delayed-dismiss.ts`'s existing 5s window already
  defers the real write until the Undo button has expired — Undo today means
  "never call `commitDelete()`"; after this change it transparently also means
  "never write the tombstone." Import has no undo today and keeps none.
- **Migration / already-imported candidates:** none needed. "Existence = pending"
  means anything already deleted (imported or dismissed before this ships) has
  no doc and nothing to retroactively tombstone — and that's correct, since
  nothing needs protecting until Android's new upload path ships anyway. The
  only transition-window effect: candidates handled on Web after this ships but
  before Android's Phase C/D ship will get a tombstone that old Android builds
  simply don't read yet — harmless, unused doc until the app updates.
- **Retention:** keep indefinitely for now. Volume is bounded by the user's own
  transaction count (same order of magnitude as `transactions` itself); a
  Firestore native TTL policy is a reasonable future addition, not needed for
  this phase — avoid building cleanup machinery nothing has asked for yet.

---

## 2. Concurrency and idempotency

A plain "read tombstone, then write candidate" is a textbook TOCTOU race. The
fix: Android's upload must be a single Firestore `runTransaction` per candidate
that (a) reads the tombstone doc, (b) if present: abort the upload and mark the
local row handled (this is also the missing **reverse sync** — Android currently
has no way to learn a candidate was handled on Web; reading the tombstone here
*is* that mechanism); (c) if absent: `set()` the candidate doc. Firestore
transactions use optimistic concurrency on every document they read — if Web's
batch writes that same tombstone doc while Android's transaction is in flight,
Firestore forces a retry, Android re-reads, sees the tombstone, and aborts.
This holds regardless of whether Web's own write is a transaction or a batch;
what matters is that Android's *read* of the tombstone is inside Android's own
transaction.

- **Multiple upload workers (same device):** already covered by the existing
  WorkManager unique chain (`"flowfi_sms_auto_scan"`, `APPEND_OR_REPLACE`) — the
  upload step should run inside that same chain, not a second one.
- **Repeated SMS broadcasts:** already covered upstream by the `UNIQUE
  message_key` sqflite constraint + `SmsDedupKey` — same local row, same doc id,
  no new handling needed.
- **Network interruption/retry:** let WorkManager's existing backoff retry the
  whole worker; each retry only re-attempts candidates still locally `pending`
  and un-tombstoned — naturally idempotent, no separate upload queue table.
- **Resume after connectivity returns / catch-up on app open:** the existing
  foreground `SmsCandidateCloudSync.sync()` should call the *same* shared
  transactional-upload function as the background path (see §4), so the
  long-documented foreground gap (`sms-candidate-contract.md` "Lifecycle")
  closes too, not just the new background path.
- **Two Web tabs importing the same candidate:** already solved — the existing
  `candidateImportKey`/idempotency-key on `TransactionRepository.createTransaction`
  is the real guard (per-tab `importsInFlight` only dedupes within one tab). The
  follow-on tombstone+delete batch is itself idempotent (delete-if-exists,
  tombstone write is the same content either way). No new mechanism required.
- **Multiple physical devices on one account:** **not solved by this proposal —
  see Unresolved Decisions, #1.**

---

## 3. User identity and privacy

The local `sms_inbox`/`sms_transaction_candidates` tables are device-wide, not
partitioned by uid.

- **Capture-time binding:** add a nullable `captured_for_uid` column (schema v10,
  additive, same pattern as v3–v9) written **once, at local insert time**, from
  whichever uid is signed in *at that moment* — not re-derived later. A row
  inserted while no one is signed in gets `captured_for_uid = NULL` and is
  **never** uploaded, even after a later sign-in (deliberately conservative:
  we can't retroactively prove whose bank message it was).
- **Upload-time check:** the shared uploader re-reads `FirebaseAuth.currentUser`
  and uploads only if `currentUser.uid == captured_for_uid`; otherwise skip
  (leave local, don't delete, don't retry-loop). This is the second guard
  against sign-out → different-user-signs-in → stale WorkManager retry firing
  under the new user's identity.
- **Background Firebase init:** `sms_background_entry.dart` currently never
  calls `Firebase.initializeApp()` — only `main.dart` does. Add the same call
  (+ the same `FirebaseFirestore.instance.settings`) to the headless entry.
  Firebase Auth persists its session in native secure storage, so the headless
  isolate calling `initializeApp()` *should* rehydrate the same signed-in user
  without `main()` ever running first in that process — **unverified, no
  device available; see Unresolved Decisions #2.**
- **Missing/expired auth:** if `currentUser` is null in the headless isolate for
  any reason, no-op (not a crash) and let it get caught up by the next
  foreground `sync()`.
- **Offline:** don't rely on Firestore's own offline write queue inside the
  headless isolate (unverified whether persistence settings carry over to a
  fresh isolate) — let a thrown/failed Firestore call become a WorkManager
  `Result.retry()` instead. Simpler, and WorkManager's retry/backoff is already
  proven for the scan step.
- **Cross-user leakage:** the `captured_for_uid` binding is the mechanism. The
  sequential-account-switch case (User A signs out, User B signs in on the same
  phone) is covered since B's scans only ever insert rows with B's own uid; A's
  older un-uploaded rows stay stuck at A's uid forever and are simply never
  uploaded under B's session.
- Unchanged: no raw SMS body, OTP, sender, or phone number is ever part of the
  candidate or tombstone document — same privacy boundary as today, tombstones
  add no new privacy surface (they contain even less than a candidate).

---

## 4. Background execution — minimum changes

Reusing the existing `SmsReceiver` → WorkManager → headless Dart → sqflite
pipeline as-is; nothing about scheduling, the prefilter, or the parsers changes.

- `sms_background_entry.dart`: add `Firebase.initializeApp(...)`.
- New shared helper, e.g. `lib/features/sms_inbox/data/sms_candidate_uploader.dart`:
  the transactional "check tombstone → mark-local-if-handled → else upload"
  function from §2/§3, used by **both** the background path and the foreground
  `SmsCandidateCloudSync.sync()`.
- `sms_background_scan.dart`: after `scanInbox()`, if
  `kSmsAutoSyncCloudUploadEnabled`, iterate newly-pending local candidates with
  `captured_for_uid == currentUser?.uid` through the uploader; surface a
  failure as a retryable `Result`, not a swallowed exception.
- `sms_auto_sync_policy.dart`: flip the flag — **last step**, after Phases B/C/D
  below are merged, not part of this first change.
- No change to native scheduling (`SmsReceiver.kt`, `SmsScanScheduler.kt`,
  `SmsScanWorker.kt`) beyond confirming the Dart call's result already maps to
  `Result.success()`/`Result.retry()` (verify at implementation time).
- Duplicate workers: reuse the existing unique chain, don't add a second one.
- Not promised: guaranteed execution after force-stop or under OEM battery
  restrictions — unchanged from today's documented limits.

---

## 5. Firestore security rules

Add, byte-identical in both `Finance_App/firestore.rules` and
`Flow-Fi-WEB/firestore.rules` (per the file's own canonical-copy requirement):

```
match /users/{uid}/smsCandidateTombstones/{id} {
  allow read: if isOwner(uid);
  allow create: if isOwner(uid);
  allow update: if false;   // handled-state is final once written
  allow delete: if isOwner(uid);
}
```

And strengthen the existing candidate rule (`firestore.rules:139`) with a
resurrection guard — the one rules change that gives a real server-side
backstop independent of any client-side logic bug:

```
match /users/{uid}/smsTransactionCandidates/{id} {
  allow read, delete: if isOwner(uid);
  allow create: if isOwner(uid) &&
    !exists(/databases/$(database)/documents/users/$(uid)/smsCandidateTombstones/$(id));
  allow update: if isOwner(uid); // Android's full-overwrite re-sync
}
```

**What rules can enforce directly:** ownership (nobody touches another user's
candidates/tombstones), and — via the `exists()` guard above — the core
invariant "a tombstoned id can never be re-created," enforced at the database
layer regardless of what any client (even a buggy future Android build) does.

**What rules cannot enforce:** which *specific* outcome was legitimate, or any
richer validation of field shapes beyond immutability (`allow update: if false`
on tombstones already covers the one invariant that matters: a dismissed
candidate can't later be silently rewritten as imported or vice versa).

---

## 6. Web integration (minimal)

- `lib/repositories/sms-transaction-candidate-repository.ts`: replace the sole
  `deleteById` write with `markHandled(candidateId, outcome, transactionId)` —
  one `writeBatch` (delete candidate + set tombstone).
- `features/transaction-candidates/lib/import-candidate.ts`: swap both
  `candidateRepository.deleteById(candidate.id)` call sites (the success path
  and `settleAlreadyImported`) for `markHandled(..., "imported", transactionId)`.
- `ignoreCandidate()`: swap for `markHandled(..., "dismissed", null)`.
- `delayed-dismiss.ts`: **no change** — the Undo window already defers the
  commit; nothing new to gate.
- `candidate-duplicate.ts` (`evaluateCandidateDuplicate`): **no change** — kept
  as the existing second guard, still useful for the multi-device gap and any
  transition-window edge case.
- No automatic transaction creation anywhere in this change — import still
  requires the same explicit user action it does today.

---

## 7. Implementation plan

**A. Schema/rules and lifecycle protection**
Files: both `firestore.rules` copies; new `SmsCandidateTombstone` model
(TS in `lib/models/`, Dart in `lib/features/sms_inbox/domain/`).
Dependencies: none. Risk: low (purely additive). Tests: extend
`tests/rules/firestore.rules.test.ts`; new Dart model serialization test.
Rollback: delete the added rule lines — nothing writes tombstones yet.

**B. Web import/dismiss integration**
Files: `sms-transaction-candidate-repository.ts`, `import-candidate.ts`.
Dependencies: A deployed to emulator/project first. Risk: medium (touches the
real import/dismiss write paths; must preserve "transaction succeeds, then
candidate is removed" ordering and the Undo UX). Tests: extend existing
import-candidate + `candidate-dismiss-undo.test.tsx` suites to assert the
tombstone write; emulator test that a resurrection attempt is rules-denied.
Rollback: revert `markHandled` to a bare delete; stray tombstones are harmless.

**C. Android UID isolation and authenticated upload**
Files: `sms_inbox_database.dart` (schema v10, `captured_for_uid` column),
`transaction_candidate_dao.dart`/`sms_inbox_dao.dart` (write it at insert),
new `sms_candidate_uploader.dart`.
Dependencies: A's rules + tombstone model. Risk: medium (new migration, new
Auth read in a previously auth-free path). Tests: Dart unit tests with the
existing `fake_cloud_firestore`/`firebase_auth_mocks` deps for uid-mismatch
skip, tombstone-present skip+local-mark, null-uid skip.
Rollback: column stays (nullable/additive); revert the uploader + call sites.

**D. Background worker integration**
Files: `sms_background_entry.dart` (Firebase init), `sms_background_scan.dart`
(call uploader), `sms_auto_sync_policy.dart` (flip the flag — last line of this
phase), existing foreground `sync()` (switch to the shared uploader).
Dependencies: A, B, C merged. Risk: high — this is the phase that actually
turns upload on. Tests: extend `sms_background_scan_test.dart`; new integration
test against the Firestore emulator simulating a WorkManager invocation.
Rollback: flip the flag back to `false` — instant, nothing else depends on it.

**E. Emulator integration QA**
Files: test-only — script the Test Matrix races (§8) against the emulator.
Dependencies: A–D. Risk: low to prod code, effort-heavy to script well.

**F. Samsung physical-device acceptance QA**
Files: none — extend the existing `adb` steps in `sms-auto-sync.md`.
Dependencies: A–E passing in emulator; needs a physical device (no adb on this
dev machine today — blocks *running* this phase, not writing it). This is the
only phase that answers the headless-Auth-rehydration question (§3,
Unresolved #2).

---

## 8. Test matrix

| Scenario | Covered by |
|---|---|
| Import then Android re-upload | Tombstone blocks re-create — C/D unit test + E emulator test |
| Dismiss then Android re-upload | Same, `outcome: dismissed` |
| Dismiss + Undo within 5s | No tombstone written — extend existing `candidate-dismiss-undo.test.tsx` |
| Concurrent import/dismiss/upload | Transaction retry semantics — E emulator race test |
| Sign-out / account switch | `captured_for_uid` mismatch skip — C unit test |
| Offline then online | WorkManager retry/backoff — D test + F adb (airplane mode) |
| App backgrounded long / reboot | Existing WorkManager persistence — F adb reboot-while-queued |
| Duplicate SMS broadcasts | Pre-existing local dedup — regression check only |
| Multiple devices, one account | **Unresolved — see below.** Manual check only: confirm no crash/corruption, accept possible duplicate Transactions as degraded-not-silent |
| Existing pending backlog | Rows with `captured_for_uid IS NULL` never auto-upload — documented behavior, not a bug |
| Permission revoked | Already handled/surfaced today — regression check only |
| Force-stop, later reopen | Already "not guaranteed" today — regression check only, F |

---

## Known correctness issue (Phase B follow-up, tracked 2026-10-24 — NOT closed)

**Import-vs-dismiss tombstone outcome mismatch.** If a dismiss and an import
race for the same candidate and dismiss's tombstone write commits first, the
import side's own later `markHandled` call cannot correct the tombstone's
`outcome` afterward — `firestore.rules` denies `update` on a tombstone
unconditionally, by design (immutability is what makes the resurrection
guard trustworthy). `sms-transaction-candidate-repository.ts` logs the
mismatch loudly (`console.error`, never swallowed) rather than hiding it,
and `tests/integration/sms-candidate-lifecycle.integration.test.ts` pins the
exact scenario, but nothing *resolves* it today.

**This is explicitly NOT classified as permanently acceptable.** It is
flagged as accepted-for-now because, in every case actually reachable
through the real `importCandidate`/`ignoreCandidate` write paths, dismiss
never creates a Transaction — so the financial ledger itself cannot become
inconsistent from this race (verified by the dedicated integration test).
What's at risk is narrower: the tombstone's own audit trail (`outcome`,
`transactionId`) can end up not reflecting what actually happened if a
genuine import transaction was created in the same window a dismiss's
tombstone won. That is a real gap, not a hypothetical one.

**Resolution plan (future work, not scheduled as part of any approved phase
yet):**
1. Narrowest fix: before `ignoreCandidate`/ the dismiss UI path even attempts
   its `markHandled` call, check whether an in-flight import for the same
   candidate id already holds the `importsInFlight` guard
   (`import-candidate.ts`) and, if so, wait for or defer to it rather than
   racing it — closes the one interleaving that can produce a real
   Transaction-vs-tombstone mismatch, without touching the rules' immutability
   guarantee.
2. More general fix (bigger, deliberately not proposed for implementation
   here): give the tombstone a short-lived "pending/contested" sub-state
   written by whichever write reaches Firestore first, read by the other
   side before it commits, so a losing call can detect the conflict and
   report a distinguishable outcome to the user instead of silently
   recording a possibly-wrong `outcome`. This would be a genuine behavior
   change to the Web lifecycle, requiring its own approval and tests — not
   done in Phase C.
3. Do nothing further, accept the gap permanently: **explicitly rejected** —
   this phase's instructions require a resolution plan, not a permanent
   write-off, and option 1 above is cheap enough that "do nothing" isn't the
   right default.

No Web lifecycle code was touched in Phase C to address this — per this
phase's scope, it is documented here only.

## Unresolved decisions (need your call before/alongside approving this)

1. **Multi-device duplication is out of scope here.** The same real-world SMS
   arriving on two devices under one account gets two different local ids
   (today's id is a local autoincrement, not content-derived) → two cloud
   candidates → possibly two Transactions if both get imported. Fixing this
   would mean changing the candidate doc id to a content-derived key instead
   of the local row id — a bigger, separate change. This proposal does not
   attempt it.
2. **Headless Firebase Auth rehydration is unverified.** Phase D assumes
   `FirebaseAuth.currentUser` resolves non-null in a cold headless isolate
   after `Firebase.initializeApp()`, with no `main()` having run first in that
   process. No adb/device available to confirm. If it turns out *not* to
   rehydrate, the fallback (persisting a session some other way, e.g. via
   `flutter_secure_storage`) is materially bigger than what's scoped above.
3. **Separate tombstone collection vs. a `status` field on the candidate
   itself.** This proposal keeps "existence = pending" and adds a sibling
   collection (zero changes to the Web listener's query), per the original
   stub's own stated preference. Flagging it explicitly as the single most
   consequential fork in this design, worth one deliberate sign-off.
4. **Tombstone retention:** proposed "keep indefinitely, revisit later" — a
   decision, not a default to assume.
5. **Scope of Phase D:** it also fixes the foreground `sync()`'s long-documented
   resurrection gap, not just the new background path. Confirm that's wanted —
   it's slightly broader than "just turn background upload on."

Stopping here for approval, per your instructions — no code changes made.
