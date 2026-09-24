import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/services/local_settings_service.dart';
import '../domain/notification_access_availability.dart';

/// Wraps the native `finance_app/notification_listener` method channel
/// (see `MainActivity.kt`) behind [NotificationAccessAvailability]. Unlike
/// `SmsPermissionService`, there is no OS dialog to trigger — the only
/// recovery path is [openSettings], which deep-links to Android's
/// notification-listener settings screen for the user to toggle manually.
class NotificationAccessService {
  const NotificationAccessService();

  static const MethodChannel _channel = MethodChannel(
    'finance_app/notification_listener',
  );

  static const String _hasShownExplanationKey =
      'sms_inbox_has_shown_notification_access_explanation';

  Future<NotificationAccessAvailability> checkStatus() async {
    if (!Platform.isAndroid) {
      return NotificationAccessAvailability.unsupportedPlatform;
    }

    final enabled = await _channel.invokeMethod<bool>('isEnabled') ?? false;
    if (enabled) return NotificationAccessAvailability.granted;
    return hasShownExplanationBefore
        ? NotificationAccessAvailability.denied
        : NotificationAccessAvailability.notRequestedYet;
  }

  /// Records that the explanation copy has been shown, then deep-links to
  /// Android's notification-listener settings screen for the user to enable
  /// FlowFi manually — there is no programmatic grant.
  Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    await LocalSettingsService.setBool(_hasShownExplanationKey, true);
    await _channel.invokeMethod<void>('openSettings');
  }

  bool get hasShownExplanationBefore =>
      LocalSettingsService.getBool(_hasShownExplanationKey);
}
