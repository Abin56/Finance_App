/// Whether the background worker CONSULTS the runtime upload switch at all
/// (Phase F3, 2026-10-25). This is a build-time capability flag, not the
/// on/off control: with it `true`, upload still happens only for the one
/// account + one device named in `users/{uid}/smsSyncConfig/backgroundUpload`
/// (see `sms_background_upload_switch.dart`), and does NOT happen when that
/// document is absent, disabled, unreadable, or names a different device.
///
/// Default behavior is therefore OFF for every account and device, and it can
/// be turned off again without rebuilding the APK by editing/deleting that
/// document. Set this to `false` in a build to remove the cloud path from that
/// build entirely (no Firestore read, no upload).
///
/// The earlier hard-coded `kSmsAutoSyncCloudUploadEnabled = false` is gone:
/// a constant `false` could not be enabled without shipping a new APK. The
/// verification gates it protected (headless Auth rehydration and a live-
/// backend proof of the tombstone transaction — see
/// `docs/sms-background-cloud-sync-architecture.md`) are now exercised through
/// the single-device activation procedure in `docs/sms-auto-sync.md`.
const bool kSmsAutoSyncCloudUploadRuntimeControlled = true;
