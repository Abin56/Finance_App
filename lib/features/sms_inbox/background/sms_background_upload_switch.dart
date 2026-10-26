import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_constants.dart';
import '../domain/sms_sync_diagnostics.dart';

/// Document id of the runtime switch under `users/{uid}/smsSyncConfig`.
const String kSmsBackgroundUploadConfigDocId = 'backgroundUpload';

/// Per-account operator stop under `users/{uid}/smsSyncConfig`
/// (`disabled: true`). Pairing can never write or clear it.
const String kSmsOperatorHoldDocId = 'operatorHold';

/// Operator-only emergency switch for every account: `smsSyncControl/global`
/// with `uploadsDisabled: true`.
const String kSmsSyncControlCollection = 'smsSyncControl';
const String kSmsSyncControlGlobalDocId = 'global';

/// SharedPreferences key holding this installation's random sync device id.
const String kSmsBackgroundInstallIdPrefsKey = 'sms_auto_sync_install_id';

/// This installation's sync device id — a random UUID created on first use and
/// kept in SharedPreferences. It is NOT a hardware identifier (no IMEI/serial/
/// ad id): it identifies one app install, and is reset by clearing app data or
/// reinstalling. The SMS Auto Sync card shows it so the operator can copy it
/// into the activation document.
///
/// Returns `null` on any storage failure (callers must then treat the device as
/// NOT authorized — fail closed).
Future<String?> getOrCreateSmsSyncInstallId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // The foreground app and the headless worker each hold their own cache of
    // the same file; re-read so one never mints a second id over the other's.
    await prefs.reload();
    final existing = prefs.getString(kSmsBackgroundInstallIdPrefsKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final created = const Uuid().v4();
    final saved = await prefs.setString(
      kSmsBackgroundInstallIdPrefsKey,
      created,
    );
    return saved ? created : null;
  } catch (_) {
    return null;
  }
}

/// Runtime kill switch / allow-list for background cloud upload (Phase F3).
///
/// Upload is permitted for a uid ONLY when ALL of these hold, read fresh from
/// the SERVER (never the local cache, so a disable takes effect on the next
/// scan rather than whenever a stale cache expires):
///
///   * `users/{uid}/smsSyncConfig/backgroundUpload` exists,
///   * its `enabled` field is exactly boolean `true`,
///   * its `deviceId` field is a non-empty string equal to THIS install's id,
///   * neither operator switch is set: the global emergency switch
///     (`smsSyncControl/global.uploadsDisabled`) nor this account's hold
///     (`users/{uid}/smsSyncConfig/operatorHold.disabled`). Since QR pairing
///     (2026-10-25) the pairing Cloud Functions write `backgroundUpload`, so
///     these separate operator-only documents are what an operator uses to stop
///     uploads in a way a user re-pairing can't undo. firestore.rules enforces
///     the same two switches on candidate writes as a server-side backstop.
///
/// Anything else — no document, `enabled: false`, a different device id, a
/// wrong field type, offline, timeout, permission denied, Firebase not
/// initialized, unreadable install id — returns `false`. There is no default-on
/// path and no cached-last-known-good path: this fails CLOSED.
///
/// The document lives under the signed-in user's own path, so a document for
/// one account can never authorize another account's upload (UID isolation),
/// and the `deviceId` pin means a second phone signed into the same account
/// stays OFF. Only the Admin SDK / Firebase console can write it —
/// `firestore.rules` denies every client write — so the app can never switch
/// itself on.
///
/// Never logs. Nothing here reads, stores or returns SMS content.
class SmsBackgroundUploadSwitch {
  SmsBackgroundUploadSwitch({
    FirebaseFirestore Function()? firestore,
    Future<String?> Function()? installId,
    this.timeout = const Duration(seconds: 10),
  }) : _firestore = firestore ?? (() => FirebaseFirestore.instance),
       _installId = installId ?? getOrCreateSmsSyncInstallId;

  final FirebaseFirestore Function() _firestore;
  final Future<String?> Function() _installId;
  final Duration timeout;

  Future<bool> isEnabledFor(String uid) async =>
      (await check(uid)).state == SmsCloudSyncState.enabled;

  /// Same decision as [isEnabledFor], but keeps "read it and it's off"
  /// ([SmsCloudSyncState.disabled]) apart from "couldn't read it"
  /// ([SmsCloudSyncState.unverified], with a privacy-safe category) so the UI
  /// can be honest. Only `enabled` ever permits upload. Never throws.
  Future<SmsUploadSwitchDecision> check(String uid) async {
    try {
      if (uid.trim().isEmpty) {
        return const SmsUploadSwitchDecision.unverified(
          SmsSyncFailureCategory.authUnavailable,
        );
      }
      final installId = await _installId();
      if (installId == null || installId.trim().isEmpty) {
        return const SmsUploadSwitchDecision.unverified(
          SmsSyncFailureCategory.unknown,
        );
      }

      final snapshot = await _firestore()
          .collection(FirestoreCollections.users)
          .doc(uid)
          .collection(FirestoreCollections.smsSyncConfig)
          .doc(kSmsBackgroundUploadConfigDocId)
          .get(const GetOptions(source: Source.server))
          .timeout(timeout);
      if (!snapshot.exists) return const SmsUploadSwitchDecision.disabled();

      final data = snapshot.data();
      if (data == null) return const SmsUploadSwitchDecision.disabled();
      if (data['enabled'] != true || data['deviceId'] != installId) {
        return const SmsUploadSwitchDecision.disabled();
      }

      // Only consulted when this device would otherwise be allowed. A read
      // failure here throws into the catch below (unverified — fail closed).
      final firestore = _firestore();
      final controls = await Future.wait([
        firestore
            .collection(kSmsSyncControlCollection)
            .doc(kSmsSyncControlGlobalDocId)
            .get(const GetOptions(source: Source.server)),
        firestore
            .collection(FirestoreCollections.users)
            .doc(uid)
            .collection(FirestoreCollections.smsSyncConfig)
            .doc(kSmsOperatorHoldDocId)
            .get(const GetOptions(source: Source.server)),
      ]).timeout(timeout);
      final globalOff = controls[0].data()?['uploadsDisabled'] == true;
      final heldOff = controls[1].data()?['disabled'] == true;
      return globalOff || heldOff
          ? const SmsUploadSwitchDecision.disabled()
          : const SmsUploadSwitchDecision.enabled();
    } catch (error) {
      return SmsUploadSwitchDecision.unverified(classifySmsSyncFailure(error));
    }
  }
}

/// Outcome of one [SmsBackgroundUploadSwitch.check]. [failure] is set only for
/// [SmsCloudSyncState.unverified].
class SmsUploadSwitchDecision {
  const SmsUploadSwitchDecision.enabled()
    : state = SmsCloudSyncState.enabled,
      failure = null;
  const SmsUploadSwitchDecision.disabled()
    : state = SmsCloudSyncState.disabled,
      failure = null;
  const SmsUploadSwitchDecision.unverified(this.failure)
    : state = SmsCloudSyncState.unverified;

  final SmsCloudSyncState state;
  final SmsSyncFailureCategory? failure;
}
