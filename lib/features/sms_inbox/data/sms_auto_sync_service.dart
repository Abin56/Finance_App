import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/sms_auto_sync_status.dart';

/// Wraps the native `finance_app/sms_auto_sync` channel (`MainActivity.kt`).
/// Enabling is an explicit opt-in; it never grants a permission itself —
/// callers request SMS permission through `SmsPermissionService` first.
class SmsAutoSyncService {
  const SmsAutoSyncService();

  static const MethodChannel _channel = MethodChannel(
    'finance_app/sms_auto_sync',
  );

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<SmsAutoSyncStatus> getStatus() async {
    if (!_supported) return const SmsAutoSyncStatus.unsupported();
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('getStatus');
      if (map == null) return const SmsAutoSyncStatus.unsupported();
      return SmsAutoSyncStatus.fromMap(map);
    } on MissingPluginException {
      // e.g. the play flavor / a build without the native half.
      return const SmsAutoSyncStatus.unsupported();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }

  Future<void> scanNow() async {
    if (!_supported) return;
    await _channel.invokeMethod<void>('scanNow');
  }
}
