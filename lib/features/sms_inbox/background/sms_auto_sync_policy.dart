/// Master switch for uploading background-captured candidates to
/// `users/{uid}/smsTransactionCandidates`.
///
/// Deliberately `false`. As of Phase D (2026-10-24) the code path itself is
/// fully wired — `sms_background_entry.dart` initializes Firebase in this
/// headless isolate, resolves a verified signed-in uid, and (only when this
/// flag is `true`) attempts a tombstone-aware upload via
/// `SmsCandidateCloudSync` — but the flag stays off because two of the
/// required verification gates (see
/// `docs/sms-background-cloud-sync-architecture.md`) remain unverified on
/// THIS development machine, not because the mechanism is unbuilt:
///
/// 1. Whether `FirebaseAuth.currentUser` actually rehydrates in a headless
///    `FlutterEngine` that never ran `main()` — needs a real Android device
///    (no SDK/adb available here).
/// 2. Whether the Dart `runTransaction` tombstone check is race-safe against
///    a REAL, concurrently-writing Firestore backend — `fake_cloud_firestore`
///    proves the logic shape only; this repo has no way to connect a Dart
///    test to a live Firestore Emulator without a device (confirmed
///    directly: `Firebase.initializeApp()` cannot complete under
///    `flutter test` on this desktop host — no platform channel).
///
/// Flip this only once both are verified on a physical device, per the
/// architecture doc's stopping conditions — not as a standalone code change.
const bool kSmsAutoSyncCloudUploadEnabled = false;
