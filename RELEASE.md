# Building FlowFi

How to produce release builds. For anything Play Store specific — the app ID
rename, Data Safety, privacy policy, store assets, submission — see
[PLAY_STORE.md](PLAY_STORE.md).

FlowFi supports two distinct release artifacts, built via an explicit Gradle
product flavor (`--flavor`) rather than an environment variable — Flutter
refuses to build without `--flavor` once flavors are declared, so it is not
possible to forget which one you meant:

| Artifact | Flavor | For | SMS Inbox | Command |
|---|---|---|---|---|
| **APK** | `sideload` | Sideloading onto your own phone | **Always on** | `flutter build apk --release --flavor sideload` |
| **AAB** | `play` | Google Play upload | **Never** | `flutter build appbundle --release --flavor play` |

> Play does not accept APKs for new apps — it requires an App Bundle. The APK
> path exists purely for personal sideloading.

## Prerequisites

Release builds require `android/key.properties` and a keystore. Neither is in the
repo (both are gitignored). Without them the build fails immediately with a
message pointing at [PLAY_STORE.md](PLAY_STORE.md#keystore-management) — debug and
profile builds are unaffected and need no keystore.

## Release APK (personal sideload)

```
flutter clean
flutter pub get
flutter build apk --release --flavor sideload
```

Output: `build/app/outputs/flutter-apk/app-sideload-release.apk`

Copy to your phone and install (enable "install from unknown sources" if
prompted). It is signed with the release keystore, so it updates in place over a
previous release build.

**This APK always includes the SMS Inbox permission** — the `sideload` flavor
keeps `READ_SMS` deterministically (see
[android/app/src/sideload/AndroidManifest.xml](android/app/src/sideload/AndroidManifest.xml)).
A Gradle verification task (`verifySmsPermissionSideloadRelease`) runs
automatically as part of this build and fails it if `READ_SMS` is ever missing
from the merged manifest, so a successful build is proof the permission is
present — not just an assumption. Never upload this flavor's output to Play —
see [PLAY_STORE.md](PLAY_STORE.md#sms-inbox-and-the-play-build) for why.

## Publishing the sideload APK (in-app update)

Already-installed sideload users do **not** re-scan the QR code for a new
release — they get an in-app update prompt (see `lib/core/update/`), which
reads the same signed manifest the `/pair` page already uses. Publishing is
one command in the **Flow-Fi-WEB** repo, run against the APK you just built
above:

```
node scripts/android-release.mjs prepare <path-to-app-sideload-release.apk> [--notes "text"] [--mandatory] [--min-supported-code <n>]
```

- `--notes "text"` — shown in the update dialog/screen. Omit to publish with
  no notes.
- `--mandatory` — every installed app below this versionCode is blocked from
  using the app until it updates (see `UpdateRequiredScreen`). Use for a
  release that fixes something that must not keep running, e.g. a data-safety
  bug.
- `--min-supported-code <n>` — same effect as `--mandatory`, but scoped to
  builds *below* `n` specifically (newer-but-still-old builds stay optional).
  Omit to carry over whatever was set for the previous release unchanged.

Then `npm run build` (stages the APK + manifest into `out/downloads/`) and
deploy Firebase Hosting as usual. That's the entire release workflow — no
separate step updates "version info" anywhere else.

**Emergency override, without a new release:** if a bad build is already out
and needs to be forced mandatory (or the minimum supported build raised)
*before* you can cut a fix, edit the `appConfig/androidUpdate` document in the
`financeapp-585eb` Firestore console directly — `{ mandatory: true }` or
`{ minSupportedVersionCode: <n> }`. This is a manual, admin-only "break glass"
switch (same convention as `smsSyncControl/global`), not something either
repo's tooling writes automatically — see `firestore.rules` in both repos.

**Known limitation:** Google Play Protect's enhanced fraud protection can
block installing this APK on some devices (it already blocks some *first*
installs — see `docs/sms-sync-pairing.md`), and an in-app-triggered install
goes through the same system installer, so it can hit the same block. The
update screen detects this and falls back to a link to `/pair` rather than
failing silently, but there's no way to make the install always succeed
in-app for affected devices.

## Release App Bundle (Play upload)

```
flutter clean
flutter pub get
flutter build appbundle --release --flavor play
```

Output: `build/app/outputs/bundle/playRelease/app-play-release.aab`

The `play` flavor removes `READ_SMS` deterministically (see
[android/app/src/play/AndroidManifest.xml](android/app/src/play/AndroidManifest.xml)),
and the same Gradle verification task (`verifySmsPermissionPlayRelease`) fails
the build if `READ_SMS` is ever present. Still worth a manual spot check before
uploading:

```
unzip -p build/app/outputs/bundle/playRelease/app-play-release.aab base/manifest/AndroidManifest.xml | strings | grep -i SMS
```

Must print nothing. (`bundletool dump manifest` is the rigorous check; the
`strings` version is a quick smoke test against a compiled protobuf manifest.)

An AAB cannot be installed directly on a device. To test one locally, use
[bundletool](https://developer.android.com/tools/bundletool), or just test the
APK — or better, ship to Play's internal testing track, which exercises the real
signing and download path.

## Bumping the version

Edit `pubspec.yaml`:

```
version: 1.0.0+1
#         ^     ^
#         |     versionCode — must strictly increase for every Play upload
#         versionName — human-readable, shown in the store and app info
```

`flutter build` feeds these into `versionCode` / `versionName` automatically via
`flutter.versionCode` / `flutter.versionName`; there is nothing to edit in
Gradle.

Rules:

- **versionCode** must strictly increase on every upload. Play permanently
  rejects a versionCode it has already seen, even from a deleted draft release.
- **versionName** is cosmetic and may repeat.
- Currently `1.0.0+1`. The first Play upload should be `1.0.0+1`; each subsequent
  upload bumps the code (`1.0.1+2`, `1.1.0+3`, …).

## What the release build does

- **R8 code shrinking**: enabled (`isMinifyEnabled = true`). Rules in
  [android/app/proguard-rules.pro](android/app/proguard-rules.pro), keeping
  Firebase, Google Play services, and `flutter_local_notifications` classes,
  which are all reached reflectively.
- **Resource shrinking**: **disabled**, deliberately. It strips Crashlytics'
  build-ID resource — only read via a native/reflection lookup, so the shrinker
  sees it as unused — which makes `FirebaseInitProvider` throw and crashes the
  app on launch. Re-enable only alongside a `keep.xml` that preserves that
  resource, and only if you verify a release build actually launches.
- **Signing**: always the release keystore for `release` builds. There is
  deliberately no debug-signing fallback — a debug-signed artifact looks valid
  locally and fails only at upload.
- **Crashlytics mapping upload**: disabled (the plugin breaks on Gradle 9). See
  the caveat in [PLAY_STORE.md](PLAY_STORE.md#firebase-production-checklist) —
  release stack traces will be obfuscated.

## Keystore

See [PLAY_STORE.md](PLAY_STORE.md#keystore-management) for creating and backing
up the keystore. Short version: it is gitignored, nothing in this repo protects
you from losing it, and losing it without Play App Signing means you can never
update the app again.
