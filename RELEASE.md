# Personal Release APK

This project is configured to build a signed release APK for **personal use on
your own phone only** — not for Play Store distribution.

## Rebuilding the APK

```
flutter clean
flutter pub get
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Copy that file to your phone and install it (enable "install from unknown
sources" if prompted). It's already signed with the release keystore below, so
it installs and updates in place over any previous release build.

## Keystore & credentials — BACK THESE UP

| File | Location | Purpose |
|---|---|---|
| Keystore | `android/app/upload-keystore.jks` | Signs the release build |
| Credentials | `android/key.properties` | Store/key passwords + alias, read by Gradle |

Both are gitignored (not committed) since they're secrets. **If you lose the
keystore, you cannot produce an update-compatible APK again** — you'd have to
uninstall the app from your phone and reinstall a freshly-signed one, losing
local app data. Back up both files somewhere safe (e.g. a password manager or
encrypted drive), outside this repo.

## Bumping the version

Edit `pubspec.yaml`:

```
version: 1.0.0+1
#         ^     ^
#         |     versionCode (must increase every time you reinstall over an existing install)
#         versionName (human-readable, shown in app info)
```

Example: `1.0.1+2` for the next build. Android requires `versionCode` to
strictly increase for an APK to be treated as an update rather than a
conflicting install.

## Notes

- Signing config lives in `android/app/build.gradle.kts` — it always uses the
  release keystore for `release` builds (no debug-signing fallback).
- R8 minification and resource shrinking are enabled for the release build
  type; ProGuard rules are in `android/app/proguard-rules.pro`.
- This setup intentionally skips Play Store requirements, App Bundles (.aab),
  Firebase App Distribution, and CI/CD — none of that is needed for a
  personal-use APK.
