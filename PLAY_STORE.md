# FlowFi — Google Play Store Release Guide

Companion to [RELEASE.md](RELEASE.md), which covers building the app. This file
covers everything specific to **publishing on Google Play**.

Nothing here has been published. This is preparation only.

---

## Current status: NOT publishable yet

Four items block a Play submission. The first three need decisions or console
access that only the account owner has.

| # | Blocker | Owner | Detail |
|---|---|---|---|
| 1 | `applicationId` is `com.example.finance_app` | You + me | Play rejects all `com.example.*`. See [Renaming the application ID](#renaming-the-application-id). |
| 2 | No keystore exists | You | `android/key.properties` and the `.jks` are absent. See [Keystore management](#keystore-management). |
| 3 | No account-deletion path | You + me | Play requires it for any app with sign-in. See [Account deletion](#account-deletion-required). |
| 4 | `READ_SMS` in the manifest | Handled | Stripped from release builds. See [SMS Inbox and the Play build](#sms-inbox-and-the-play-build). |

Already compliant, verified:

- `targetSdk` / `compileSdk` resolve to **36** via `flutter.targetSdkVersion`
  (Flutter 3.44.6), `minSdk` **24** — meets the current Play target-API rules.
- `dart analyze` → **0 issues**. No `print()`, no `TODO`/`FIXME` in `lib/`.
- [firestore.rules](firestore.rules) is correctly scoped: a user can only read
  and write below `/users/{their own uid}`.
- R8 code shrinking is on for release.

---

## Renaming the application ID

**Do not edit `applicationId` on its own.** It is duplicated in
[google-services.json](android/app/google-services.json), and the
`com.google.gms.google-services` Gradle plugin hard-fails the build with
`No matching client found for package name` when the two disagree. The Firebase
side must be registered *first*, or the project stops building.

Agreed target ID: **`dev.abinjohn.flowfi`** (only valid if you control
`abinjohn.dev`; an applicationId is permanent once published — it can never be
changed for the life of the listing).

Order of operations:

1. **Firebase Console → Project settings → Add app → Android.**
   Register package name `dev.abinjohn.flowfi`. Keep the existing
   `com.example.finance_app` app registered until the migration is done.
2. Download the new `google-services.json` and replace
   `android/app/google-services.json`. It will contain *both* clients, which is
   what lets you cut over without breaking the old build.
3. Add the release **SHA-1 and SHA-256** signing fingerprints to the new Firebase
   app. Google Sign-In will fail at runtime without them — this is the single
   most common post-rename breakage, and it does not show up until you actually
   try to sign in on a release build. Get them with:
   ```
   keytool -list -v -keystore android/app/upload-keystore.jks -alias upload
   ```
   If you use Play App Signing (recommended), you must **also** add the
   fingerprint Play shows under *Release → Setup → App signing*, because Play
   re-signs your upload with a different key.
4. Change `applicationId` in [android/app/build.gradle.kts](android/app/build.gradle.kts).
5. Change `namespace` in the same file to match.
6. Move the Kotlin source to the matching directory and update its `package`:
   `android/app/src/main/kotlin/com/example/finance_app/MainActivity.kt`
   → `android/app/src/main/kotlin/dev/abinjohn/flowfi/MainActivity.kt`
7. `flutter clean && flutter pub get`, then rebuild and **sign in on a real
   release build** to confirm step 3.

> `namespace` (the R/BuildConfig package) and `applicationId` (the Play identity)
> are technically independent, but keeping them equal avoids confusion later.

---

## Keystore management

Neither `android/key.properties` nor the keystore currently exists. Until they
do, release builds fail fast with a message pointing here — debug and profile
builds are unaffected.

Create the upload keystore:

```
keytool -genkey -v -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (gitignored — never commit it):

```
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=upload-keystore.jks
```

`storeFile` is resolved relative to `android/app/`, so a bare filename means
`android/app/upload-keystore.jks`.

### Back these up, off-machine

Both files are gitignored, so **nothing in this repo protects you from losing
them.** Copy them to a password manager or encrypted drive.

- **With Play App Signing** (recommended, and the default for new apps): Google
  holds the real app signing key. If you lose the *upload* key you can request a
  reset from Play support — recoverable.
- **Without Play App Signing**: losing the key means you can never update the
  listing again. You would have to publish a new app under a new applicationId
  and lose all installs and reviews.

---

## SMS Inbox and the Play build

**Release builds ship without `READ_SMS`, deliberately.**

Google Play restricts the SMS permission group to apps that are the user's
**default SMS handler**. Parsing bank transaction texts in a finance app is not
an approved use case, and exception requests for "SMS banking transaction
features" are denied on the grounds that SMS access is not core functionality for
a non-default-handler app. Bluecoins, a well-established personal finance app,
had to strip SMS permissions for exactly this reason.

The risk is not scoped to the feature — declaring `READ_SMS` without an approved
use case can sink **the whole listing**.

How it works:

- [android/app/src/release/AndroidManifest.xml](android/app/src/release/AndroidManifest.xml)
  applies `tools:node="remove"` to `READ_SMS` for `release` builds only.
- This is a merge-time override rather than an edit to `src/main`, because
  `flutter_sms_inbox` contributes `READ_SMS` from its **own library manifest**.
  Deleting the line from `src/main` would not keep it out of the merged manifest;
  the app manifest winning the merge is what does.
- Stripping is the **default**, so forgetting a flag produces a compliant upload
  rather than a rejected one.

For a personal, sideloaded build that keeps SMS:

```
FLOWFI_SMS=1 flutter build apk --release
```

That build is **not valid for Play upload**. The Gradle log prints a warning when
the flag is active.

> Verify before every upload — see [Pre-submission checklist](#pre-submission-checklist).
> The SMS Inbox UI must degrade gracefully when the permission is absent, since
> that is now the normal state for all Play users.

---

## Account deletion (required)

Play requires that any app offering account creation also offers **account
deletion**, via both:

1. an **in-app** path, and
2. a **publicly reachable web URL** you enter in Play Console, usable without
   installing the app.

FlowFi signs users in with Google but has **no deletion path anywhere in `lib/`**
(verified by search). This must be built before submission. Deleting the Firebase
Auth user is not sufficient on its own — the user's `/users/{uid}` Firestore
subtree must go too, which for a nested structure generally means a callable
Cloud Function or the `firebase-admin` SDK, since client-side recursive deletes
are not atomic.

---

## Permissions inventory

This is the **verified** list, read out of the merged release manifest
(`build/app/intermediates/merged_manifest/release/.../AndroidManifest.xml`) — not
just what `src/main` declares. Most of these are contributed by plugin library
manifests and never appear in the project's own source.

To regenerate this list after changing dependencies:

```
cd android && ./gradlew :app:processReleaseMainManifest
grep -o 'uses-permission[^>]*android:name="[^"]*"' \
  ../build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml
```

`build/app/outputs/logs/manifest-merger-release-report.txt` attributes every
entry to the exact library that introduced it.

### Declared in `src/main`

| Permission | Verdict | Why |
|---|---|---|
| `INTERNET` | **Keep** | Firestore sync, Firebase Auth, Crashlytics, Analytics. |
| `POST_NOTIFICATIONS` | **Keep** | Bill/EMI reminders via `flutter_local_notifications`. Runtime-requested on API 33+. |
| `RECEIVE_BOOT_COMPLETED` | **Keep** | Scheduled reminders do not survive reboot; the boot receiver re-arms them. |
| `SCHEDULE_EXACT_ALARM` | **Review** | See [below](#schedule_exact_alarm-needs-a-decision). |
| `READ_SMS` | **Removed from release** | Play policy. See [above](#sms-inbox-and-the-play-build). Verified absent from the merged release manifest. |

### Contributed by plugins

| Permission | Source | Verdict |
|---|---|---|
| `ACCESS_NETWORK_STATE` | Firebase | Keep — normal permission, no prompt. |
| `WAKE_LOCK`, `VIBRATE` | `flutter_local_notifications` | Keep — needed to fire reminders. |
| `USE_BIOMETRIC`, `USE_FINGERPRINT` | `local_auth` | Keep — biometric app-lock. |
| `READ_GSERVICES` | Google Play services | Keep — unavoidable. |
| `BIND_GET_INSTALL_REFERRER_SERVICE` | Firebase Analytics | Keep — install attribution. |
| `<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX | Keep — self-scoped, auto-generated. |
| `com.google.android.gms.permission.AD_ID` | Firebase Analytics | **Consider removing** — see below. |
| `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION` | `play-services-measurement-api` | **Consider removing** — see below. |

### The advertising ID permissions are worth removing

`firebase_analytics` pulls in `play-services-measurement-api`, which injects
`AD_ID` and the AdServices permissions. Nothing in FlowFi asks for them.

The consequence is a compliance obligation, not a crash: shipping `AD_ID` means
you **must** declare "collects Advertising ID" on the Data Safety form and answer
the Advertising ID question in App Content. Declaring it while the app shows no
ads is a poor look for a finance app, and a form/behaviour mismatch is a common
rejection cause.

FlowFi has no ads and no attribution needs, so the permission buys nothing. To
drop it, add to [android/app/src/release/AndroidManifest.xml](android/app/src/release/AndroidManifest.xml):

```xml
<uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove" />
<uses-permission android:name="android.permission.ACCESS_ADSERVICES_AD_ID" tools:node="remove" />
<uses-permission android:name="android.permission.ACCESS_ADSERVICES_ATTRIBUTION" tools:node="remove" />
```

> **Not applied** — it is a genuine trade-off, not a pure win: it degrades
> Firebase Analytics attribution. Since Analytics is currently wired up and this
> task must not change app behaviour unasked, it is your call. Removing it is the
> recommendation for a personal finance tracker.

### `SCHEDULE_EXACT_ALARM` needs a decision

On Android 13+ this is **not** grantable by a normal app install — Play gates it
behind an approved use case (alarms, timers, calendar events). Bill reminders are
a borderline fit and can draw review scrutiny.

`USE_EXACT_ALARM` (Android 14+) is auto-granted but restricted to *alarm clock
and calendar* apps, and is riskier for a finance app.

The lowest-risk option is `scheduleExactAlarm` → **inexact** scheduling
(`AndroidScheduleMode.inexactAllowWhileIdle`), which needs no special permission
and is entirely adequate for a bill reminder that does not need to-the-minute
precision. Recommended unless you specifically want exact-minute reminders.

> Not changed here: it touches the shared manifest and the reminder scheduling
> path, which is live business logic and out of scope for this task.

---

## Security review

| Area | Status |
|---|---|
| Firestore rules | **Good.** User-scoped, auth-required, no public reads. |
| Auth | Google Sign-In via Firebase. No custom credential handling. |
| API keys | `google-services.json` is committed. **This is fine** — the Firebase Android API key is a client identifier, not a secret; it is extractable from any APK regardless. Firestore rules are the actual access control. |
| Secrets in repo | None found. Keystore and `key.properties` are correctly gitignored. |
| PIN storage | **Good.** Salted hash in the platform keystore via `flutter_secure_storage` — never in plain prefs. See [secure_key_service.dart](lib/core/services/security/secure_key_service.dart). |
| Local cache at rest | **Plaintext.** Known and documented in-code: Firestore's offline cache is a local SQLite DB that the SDK cannot encrypt. Mitigated by app-lock + OS sandboxing; only a rooted device or a full backup exposes it. |
| Backup | **Needs attention** — see below. |

### `allowBackup` — fixed

> **Applied.** `android:allowBackup="false"`, `android:fullBackupContent="false"`,
> and `android:dataExtractionRules="@xml/data_extraction_rules"` are now set in
> `src/main/AndroidManifest.xml`. Verified present in the merged debug manifest
> (no plugin overrides them). Retained below for the reasoning.

The manifest declared no `android:allowBackup` and no `dataExtractionRules`, so
it **defaulted to `true`**. Two consequences:

1. **App-lock can break on device restore.** Android Auto Backup copies
   `flutter_secure_storage`'s encrypted PIN blob to Google Drive, but the
   Android Keystore master key is hardware-bound and **is not backed up**. After
   a restore onto a new device, the blob is present but undecryptable — the PIN
   check reads back garbage or throws. This is a well-known
   `flutter_secure_storage` failure mode.
2. **The plaintext Firestore cache is backed up to Drive.** Every synced
   transaction, balance, and account name leaves the device in a form neither the
   app nor the user controls — and it must be disclosed on the Data Safety form.

The fix applied is `android:allowBackup="false"` *plus*
[data_extraction_rules.xml](android/app/src/main/res/xml/data_extraction_rules.xml).
Both are needed: on API 31+ (FlowFi targets 36) `allowBackup="false"` only stops
Drive backup, while device-to-device transfer is governed by
`dataExtractionRules` and would otherwise still copy the undecryptable PIN blob
onto the new device. `fullBackupContent="false"` covers API 30 and below. Since
FlowFi's data already round-trips through Firestore, neither path buys the user
anything.

---

## Data Safety form

Play Console → *Policy → App content → Data safety*. Declare honestly; mismatches
between the form and observed app behaviour are a common rejection cause.

| Data type | Collected | Shared | Purpose | Notes |
|---|---|---|---|---|
| Email address | Yes | No | Account management | Firebase Auth via Google Sign-In. |
| Name, profile photo | Yes | No | Account management | Supplied by Google Sign-In. |
| **Financial info** (user-entered transactions, balances, accounts, debts) | Yes | No | App functionality | Firestore. The most scrutinised category — be precise. |
| Crash logs | Yes | Yes → Google | Diagnostics | Firebase Crashlytics. |
| Diagnostics / app interactions | Yes | Yes → Google | Analytics | Firebase Analytics. |
| Device / installation IDs | Yes | Yes → Google | Analytics, diagnostics | Firebase. |
| **Advertising ID** | Yes, unless removed | Yes → Google | Analytics | The manifest ships `AD_ID` via Firebase Analytics. Must be declared **unless** you strip it — see [above](#the-advertising-id-permissions-are-worth-removing). |
| SMS messages | **No** (Play build) | No | — | Only if a build ships `READ_SMS`. Verified absent from release builds. |

Required answers:

- **Encrypted in transit:** Yes (Firebase is HTTPS/TLS throughout).
- **Encrypted at rest:** Server-side yes (Google Cloud). Be careful claiming
  on-device encryption — the local cache is plaintext.
- **Users can request deletion:** must be **Yes**, which depends on
  [Account deletion](#account-deletion-required) shipping first.

> Firebase Analytics and Crashlytics both collect on first run with **no consent
> gate** in this app. That is acceptable for Play's Data Safety form as long as
> it is declared, but if you intend to distribute in the EU/UK, GDPR consent is a
> separate obligation this app does not currently meet.

---

## Privacy policy

Required for every app that collects personal data — FlowFi does. It must be a
public URL (not a PDF, not gated) entered in Play Console, and it must cover:

- what is collected (see the Data Safety table above)
- that data is stored in Google Firebase, and that Crashlytics/Analytics share
  diagnostics with Google
- how to request deletion, with the same URL as the deletion requirement
- a contact address

GitHub Pages or a Notion public page is sufficient. It must be live before
submission.

---

## Store assets checklist

Play Console rejects an incomplete listing, so gather these first.

| Asset | Spec | Status |
|---|---|---|
| App icon (Play listing) | 512×512 PNG, 32-bit, no alpha | Derive from `assets/app_icon/app_icon.png` |
| Feature graphic | 1024×500 PNG/JPG, no alpha | **Missing — required** |
| Phone screenshots | 2–8, min 320px, 16:9 or 9:16 | **Missing — required** |
| 7" tablet screenshots | Optional | Only if declaring tablet support |
| 10" tablet screenshots | Optional | Only if declaring tablet support |
| Short description | ≤80 chars | Missing |
| Full description | ≤4000 chars | Missing |
| App category | e.g. Finance | Decide |
| Content rating questionnaire | — | Complete in Console |

In-app icons (launcher, adaptive, splash) are **already configured** —
`flutter_launcher_icons` is set up in [pubspec.yaml](pubspec.yaml), adaptive
foreground/background exist, and the splash uses `launch_background.xml`.
`android:roundIcon` is not declared; it is optional and only affects API 25
launchers, which is below relevance for `minSdk 24` in practice.

> Screenshots must show the real app. Mockups with invented data in device frames
> are fine, but do not show features the app lacks.

---

## Firebase production checklist

- [ ] New Android app registered for `dev.abinjohn.flowfi`
- [ ] Release SHA-1 **and** SHA-256 added (plus the Play App Signing fingerprint)
- [ ] `google-services.json` replaced in `android/app/`
- [ ] Firestore rules deployed to the production project (`firebase deploy --only firestore:rules`)
- [ ] Firestore in **production mode**, not test mode (test mode rules expire and fall open)
- [ ] Crashlytics receiving events from a release build
- [ ] Budget alert set on the Firebase/GCP billing account
- [ ] Google Sign-In verified **on a Play-signed build**, not just locally

> Crashlytics mapping-file upload is **disabled** in
> [build.gradle.kts](android/app/build.gradle.kts) (the plugin breaks on Gradle 9).
> Release crash reports will therefore have **obfuscated, unreadable stack
> traces**. That was a defensible trade for a personal APK; for a public release
> it means production crashes are largely undiagnosable. Worth revisiting.

---

## Pre-submission checklist

Build and hygiene:

- [ ] `dart analyze` → 0 issues
- [ ] `flutter test` → all passing
- [ ] `flutter build appbundle --release` succeeds
- [ ] Version bumped in [pubspec.yaml](pubspec.yaml) (see [RELEASE.md](RELEASE.md))
- [ ] Release build launches, signs in, and syncs on a **real device**
- [ ] **Confirm `READ_SMS` is absent from the uploaded artifact:**
      ```
      unzip -p build/app/outputs/bundle/release/app-release.aab base/manifest/AndroidManifest.xml | strings | grep -i SMS
      ```
      (must print nothing; `bundletool dump manifest` is the rigorous check)

Blockers:

- [ ] `applicationId` no longer `com.example.*`
- [ ] Keystore created and backed up off-machine
- [ ] Account deletion shipped (in-app + web URL)
- [x] `allowBackup` decision applied — set to `false` with `dataExtractionRules`

Play Console:

- [ ] Privacy policy URL live
- [ ] Data safety form completed
- [ ] Content rating questionnaire completed
- [ ] Target audience declared
- [ ] Financial features declaration (Play asks specifically about finance apps;
      FlowFi is a personal tracker with no payments, which keeps this simple —
      but it must still be answered)
- [ ] Store listing assets uploaded
- [ ] Internal testing track release verified before production

> Ship to the **internal testing track first**. It exercises Play App Signing and
> the real download path, and catches signing/Firebase fingerprint problems that
> never reproduce on a locally-built APK.

---

## Performance, accessibility, and quality review

Findings from a read-through. **Nothing here was changed** — all of it is either
working code or a trade-off worth your judgement, and this task was scoped to
avoid touching behaviour. Ordered by what actually matters.

### Transaction history is not virtualized — the one real perf issue

[transactions_screen.dart:253](lib/features/transactions/presentation/screens/transactions_screen.dart#L253)
(and `:315`, and [expenses_screen.dart:60](lib/features/expense/presentation/screens/expenses_screen.dart#L60))
render with `ListView(children: [...])`, which builds **every** child eagerly, not
lazily. Each transaction is additionally wrapped in a `Dismissible`.

This is fine today and will stay fine for a while. It degrades with history size,
which for a finance app grows without bound — a few years of daily transactions
means thousands of widgets built on every open, with the memory and first-frame
cost paid up front.

The fix is `ListView.builder`/`SliverList` over a pre-flattened
`[header, txn, txn, header, …]` list, since the current structure is a nested
`for` over date groups and cannot be indexed directly. That is a real refactor of
a working screen with real regression risk, so it is deliberately left alone —
worth doing before the history gets large, not before the first release.

Repo-wide: only 1 file uses `ListView.builder`/`SliverList` against 38
`ListView(` call sites. Most of the rest are bounded (settings, forms, sheets)
and are genuinely fine non-lazy.

### Accessibility — better than typical

- **Text scaling: respected.** No `textScaleFactor` / `TextScaler.linear`
  overrides anywhere, so OS font-size settings work. This is the most common
  Flutter a11y failure and FlowFi does not have it.
- **Screen readers: adequate.** 63 `tooltip:` across 65 `IconButton`s — tooltips
  supply the semantic label, so icon-only controls are announced. There are 0
  explicit `Semantics(` widgets, but Material defaults plus tooltips cover the
  common cases. Worth a real TalkBack pass before release; not a blocker.
- **Dark mode:** fully supported (`AppTheme.light` / `AppTheme.dark` +
  `themeMode`), including a `values-night` splash theme.
- **Orientation:** no `setPreferredOrientations` lock, so the app rotates freely.
  Verify the dashboard and charts in landscape, or lock to portrait if they were
  never designed for it. Play does not require landscape, but a broken landscape
  layout is a review risk.
- **Touch targets / contrast:** not machine-verifiable here. Spot-check against
  the 48dp minimum.

### Quality

- `const` is used heavily (~2260 sites) — rebuild hygiene is good.
- Crash reporting is wired correctly in [main.dart](lib/main.dart):
  `FlutterError.onError` and `PlatformDispatcher.instance.onError` both route to
  Crashlytics. But see the mapping-file caveat above — those reports arrive
  **obfuscated**, which is the weakest link in production diagnostics.
- No `print()`, no `TODO`/`FIXME` in `lib/`.
- `flutter test`: **599 passing**.

### Startup

`main()` awaits `Firebase.initializeApp`, `LocalSettingsService.init()`, and
`ReminderNotificationService.init()` before `runApp`. That is correct for
correctness' sake — but each one is blocking time on a cold start before the
first frame. If startup ever feels slow, `ReminderNotificationService.init()` is
the best candidate to move behind the first frame, since nothing on the initial
route depends on it. Measure before changing; do not optimize this on spec.

### Known future breakage (not a blocker)

The Gradle build prints:

```
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
firebase_analytics, share_plus
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

Nothing to do today — it needs upstream fixes in those plugins. Expect it to
become a hard failure on a future Flutter upgrade, and do not upgrade Flutter
immediately before a release deadline.
