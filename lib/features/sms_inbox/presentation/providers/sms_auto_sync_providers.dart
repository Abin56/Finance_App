import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sms_auto_sync_service.dart';
import '../../domain/sms_auto_sync_status.dart';
import '../../domain/sms_availability.dart';
import 'sms_inbox_providers.dart';

final smsAutoSyncServiceProvider = Provider<SmsAutoSyncService>(
  (ref) => const SmsAutoSyncService(),
);

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
    return state.value?.isEffective ?? false;
  }

  Future<void> disable() async {
    await ref.read(smsAutoSyncServiceProvider).setEnabled(false);
    await refresh();
  }

  Future<void> scanNow() async {
    await ref.read(smsAutoSyncServiceProvider).scanNow();
    await refresh();
  }
}

final smsAutoSyncProvider =
    AsyncNotifierProvider.autoDispose<SmsAutoSyncNotifier, SmsAutoSyncStatus>(
      SmsAutoSyncNotifier.new,
    );
