import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/sms_auto_sync_service.dart';
import '../../data/sms_sync_diagnostics_store.dart';
import '../../domain/sms_auto_sync_status.dart';
import '../../domain/sms_availability.dart';
import '../../domain/sms_sync_diagnostics.dart';
import '../../pairing/sms_pairing_providers.dart';
import '../../pairing/sms_pairing_service.dart';
import 'sms_inbox_providers.dart';

final smsAutoSyncServiceProvider = Provider<SmsAutoSyncService>(
  (ref) => const SmsAutoSyncService(),
);

const _kUnpairPending = 'sms_auto_sync_off_unpair_pending';

/// Revokes this install's Web pairing for Auto Sync OFF. Remembers a failed
/// attempt so [retrySmsUnpairIfPending] can finish it later. Never throws.
Future<SmsAutoSyncOffResult> revokeSmsPairingForAutoSyncOff(
  SmsPairingService service,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (await readSmsPairedUid() == null) {
    await prefs.remove(_kUnpairPending);
    return SmsAutoSyncOffResult.notPaired;
  }
  try {
    await service.disconnectThisDevice();
    await prefs.remove(_kUnpairPending);
    return SmsAutoSyncOffResult.unpaired;
  } catch (_) {
    await prefs.setBool(_kUnpairPending, true);
    return SmsAutoSyncOffResult.unpairPending;
  }
}

/// On app resume: finishes an Auto Sync OFF whose revocation couldn't reach
/// the server — only when one is actually pending and Auto Sync is still off.
Future<void> retrySmsUnpairIfPending(
  SmsPairingService service,
  SmsAutoSyncService autoSync,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kUnpairPending) != true) return;
    if ((await autoSync.getStatus()).enabled) {
      await prefs.remove(_kUnpairPending);
      return;
    }
    await revokeSmsPairingForAutoSyncOff(service);
  } catch (_) {}
}

/// What turning Auto Sync off did to the Web pairing.
enum SmsAutoSyncOffResult {
  /// This install wasn't paired — nothing to revoke.
  notPaired,

  /// The server revoked the pairing; Web is back on its pairing screen.
  unpaired,

  /// Couldn't reach the server; retried on next app resume.
  unpairPending,
}

/// Native Auto Sync status. Re-read explicitly (after toggling, and when the
/// card is shown) — the worker updates it out-of-process, so there is
/// nothing to subscribe to.
class SmsAutoSyncNotifier extends AutoDisposeAsyncNotifier<SmsAutoSyncStatus> {
  @override
  Future<SmsAutoSyncStatus> build() =>
      ref.watch(smsAutoSyncServiceProvider).getStatus();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(smsAutoSyncServiceProvider).getStatus(),
    );
  }

  /// Explicit opt-in. Requests SMS permission first (never silently), and
  /// only turns Auto Sync on when the OS actually granted it. Returns whether
  /// Auto Sync ended up enabled.
  Future<bool> enable() async {
    final availability = await ref
        .read(smsPermissionServiceProvider)
        .requestPermission();
    if (availability != SmsAvailability.granted) {
      await refresh();
      return false;
    }
    await ref.read(smsAutoSyncServiceProvider).setEnabled(true);
    await refresh();
    final effective = state.value?.isEffective ?? false;
    await ref
        .read(smsDevicePresenceReporterProvider)
        .report(
          permission: availability,
          autoSyncEnabled: effective,
          force: true,
        );
    // A paired phone tells FlowFi Web (no-op when this install isn't paired).
    await ref
        .read(smsDeviceStatusReporterProvider)
        .report(
          permission: availability,
          autoSyncEnabled: effective,
          force: true,
        );
    return effective;
  }

  /// Auto Sync OFF: stops scheduling (the native side cancels queued and
  /// retrying WorkManager scans), then ENDS the Web pairing through the
  /// server's `revokeSmsDeviceCallable` — Web sync needs a fresh QR pairing
  /// after this. Imported candidates, transactions and SMS stay untouched.
  ///
  /// An upload already committed before this can't be rolled back; one still
  /// in flight is refused by firestore.rules once the revocation lands.
  /// Offline: the revocation is retried on the next app resume
  /// ([retryPendingRevocation]); until then the foreground upload is held
  /// back locally because Auto Sync is off.
  Future<SmsAutoSyncOffResult> disable() async {
    await ref.read(smsAutoSyncServiceProvider).setEnabled(false);
    await refresh();
    // Sent while still paired, so the server accepts it.
    await ref
        .read(smsDeviceStatusReporterProvider)
        .report(autoSyncEnabled: false, force: true);
    final result = await revokeSmsPairingForAutoSyncOff(
      ref.read(smsPairingServiceProvider),
    );
    await ref
        .read(smsDevicePresenceReporterProvider)
        .report(autoSyncEnabled: false, force: true);
    ref.invalidate(smsPairedUidProvider);
    return result;
  }

  Future<void> scanNow() async {
    await ref.read(smsAutoSyncServiceProvider).scanNow();
    await refresh();
  }
}

/// Local background-sync health (Phase F4). Watches the native status so it
/// re-reads whenever that does; read-only, local storage only.
final smsSyncDiagnosticsProvider =
    FutureProvider.autoDispose<SmsSyncDiagnostics>((ref) async {
      ref.watch(smsAutoSyncProvider);
      return const SmsSyncDiagnosticsStore().read();
    });

final smsAutoSyncProvider =
    AsyncNotifierProvider.autoDispose<SmsAutoSyncNotifier, SmsAutoSyncStatus>(
      SmsAutoSyncNotifier.new,
    );
