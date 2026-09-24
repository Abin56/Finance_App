import 'package:permission_handler/permission_handler.dart';

enum CameraPermissionResult { granted, denied, permanentlyDenied }

/// Thin wrapper around `permission_handler`'s `Permission.camera` —
/// mirrors `SmsPermissionService`'s status-then-request shape, scoped down
/// since Smart Import only ever needs "can I use the camera right now",
/// not SMS Inbox's richer first-ask/re-ask/settings-nudge history.
class CameraPermissionService {
  const CameraPermissionService();

  /// Returns [CameraPermissionResult.granted] immediately if already
  /// granted; otherwise triggers the OS permission dialog (unless it's
  /// already permanently denied, in which case asking again would be a
  /// no-op dialog the OS silently ignores).
  Future<CameraPermissionResult> ensureGranted() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return CameraPermissionResult.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionResult.permanentlyDenied;
    }

    final requested = await Permission.camera.request();
    if (requested.isGranted) return CameraPermissionResult.granted;
    if (requested.isPermanentlyDenied || requested.isRestricted) {
      return CameraPermissionResult.permanentlyDenied;
    }
    return CameraPermissionResult.denied;
  }

  Future<void> openSettings() => openAppSettings();
}
