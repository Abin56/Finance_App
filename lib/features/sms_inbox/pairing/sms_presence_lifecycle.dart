import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notification_access_service.dart';
import '../data/sms_auto_sync_service.dart';
import '../data/sms_permission_service.dart';
import '../domain/notification_access_availability.dart';
import '../domain/sms_availability.dart';
import '../presentation/providers/sms_auto_sync_providers.dart';
import 'sms_pairing_providers.dart';
import 'sms_pairing_service.dart';

/// App-lifetime presence for FlowFi Web: on launch, sign-in and every resume
/// it re-verifies SMS permission and notification access with Android (never
/// from a toggle) and reports them with the Auto Sync state; while the app is
/// open it heartbeats every [interval]; on pause it reports `background`.
/// The web turns a heartbeat older than ~2.5 minutes into "offline".
class SmsPresenceLifecycle {
  SmsPresenceLifecycle(
    this._ref, {
    this.interval = const Duration(seconds: 60),
  });

  final Ref _ref;
  final Duration interval;
  Timer? _timer;
  bool _foreground = false;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  void onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(resumed());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(paused());
    }
  }

  Future<void> resumed() async {
    if (!_supported) return;
    _foreground = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    await refresh(force: true);
    await retrySmsUnpairIfPending(
      _ref.read(smsPairingServiceProvider),
      const SmsAutoSyncService(),
    );
  }

  Future<void> paused() async {
    if (!_supported) return;
    _foreground = false;
    _timer?.cancel();
    _timer = null;
    await _ref
        .read(smsDevicePresenceReporterProvider)
        .report(foreground: false, force: true);
  }

  /// Re-reads the real OS state and reports it (identical reports within the
  /// reporter's min interval are skipped unless [force]). Never throws.
  Future<void> refresh({bool force = false}) async {
    if (!_supported) return;
    try {
      final status = await const SmsAutoSyncService().getStatus();
      final SmsAvailability permission;
      if (status.supported &&
          status.readSmsGranted &&
          status.receiveSmsGranted) {
        permission = SmsAvailability.granted;
      } else {
        final checked = await const SmsPermissionService().checkStatus();
        // READ_SMS without RECEIVE_SMS isn't enough for Auto Sync.
        permission = checked == SmsAvailability.granted && status.supported
            ? SmsAvailability.denied
            : checked;
      }
      NotificationAccessAvailability? notification;
      try {
        notification = await const NotificationAccessService().checkStatus();
      } catch (_) {}
      await _ref
          .read(smsDevicePresenceReporterProvider)
          .report(
            foreground: _foreground,
            permission: permission,
            notificationAccess: notification,
            autoSyncEnabled: status.enabled,
            label: await readSmsDeviceLabel(),
            force: force,
          );
    } catch (_) {}
  }

  void dispose() => _timer?.cancel();
}

final smsPresenceLifecycleProvider = Provider<SmsPresenceLifecycle>((ref) {
  final lifecycle = SmsPresenceLifecycle(ref);
  ref.onDispose(lifecycle.dispose);
  return lifecycle;
});
