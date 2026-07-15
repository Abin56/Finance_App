import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/local_settings_service.dart';
import '../domain/sms_availability.dart';

/// Wraps `permission_handler`'s `Permission.sms` behind [SmsAvailability],
/// and tracks whether we've ever asked before (via [LocalSettingsService])
/// so the UI can show the plain-language explanation before the first OS
/// dialog, and "Grant Permission" after a denial — per the feature spec's
/// permission-flow copy.
class SmsPermissionService {
  const SmsPermissionService();

  static const String _hasRequestedKey = 'sms_inbox_has_requested_permission';

  Future<SmsAvailability> checkStatus() async {
    if (!Platform.isAndroid) return SmsAvailability.unsupportedPlatform;

    final status = await Permission.sms.status;
    return _mapStatus(status);
  }

  /// Actually triggers the OS permission dialog. Callers should show the
  /// explanation copy first (before ever calling this), per the spec.
  Future<SmsAvailability> requestPermission() async {
    if (!Platform.isAndroid) return SmsAvailability.unsupportedPlatform;

    await LocalSettingsService.setBool(_hasRequestedKey, true);
    final status = await Permission.sms.request();
    return _mapStatus(status);
  }

  Future<void> openSettings() => openAppSettings();

  bool get hasRequestedBefore => LocalSettingsService.getBool(_hasRequestedKey);

  SmsAvailability _mapStatus(PermissionStatus status) {
    if (status.isGranted) return SmsAvailability.granted;
    if (status.isPermanentlyDenied || status.isRestricted) return SmsAvailability.permanentlyDenied;
    if (!hasRequestedBefore) return SmsAvailability.notRequestedYet;
    return SmsAvailability.denied;
  }
}
