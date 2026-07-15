# Building FlowFi

How to produce release builds. For anything Play Store specific — the app ID
rename, Data Safety, privacy policy, store assets, submission — see
[PLAY_STORE.md](PLAY_STORE.md).

FlowFi supports two distinct release artifacts:

| Artifact | For | SMS Inbox | Command |
|---|---|---|---|
| **APK** | Sideloading onto your own phone | Optional (opt-in) | `flutter build apk --release` |
| **AAB** | Google Play upload | **Never** | `flutter build appbundle --release` |

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
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Copy to your phone and install (enable "install from unknown sources" if
prompted). It is signed with the release keystore, so it updates in place over a
previous release build.

**This APK does not include the SMS Inbox permission.** Release builds strip
`READ_SMS` by default so that a Play upload is compliant unless you explicitly
opt out. To build a personal APK that keeps SMS:

```
FLOWFI_SMS=1 flutter build apk --release
```

PowerShell:

```
$env:FLOWFI_SMS="1"; flutter build apk --release; Remove-Item Env:\FLOWFI_SMS
```

Gradle logs a warning when the flag is active. Never upload that artifact to Play
— see [PLAY_STORE.md](PLAY_STORE.md#sms-inbox-and-the-play-build) for why.

## Release App Bundle (Play upload)

```
flutter clean
flutter pub get
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Do **not** set `FLOWFI_SMS` for this build. Verify the result before uploading:

```
unzip -p build/app/outputs/bundle/release/app-release.aab base/manifest/AndroidManifest.xml | strings | grep -i SMS
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
