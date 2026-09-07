import 'dart:io';

/// What happened when the user tried to scan with the camera. Kept separate
/// from [File] itself so the camera capture screen can react to every
/// outcome (cancelled, permission denied, no camera hardware) with the
/// right plain-language message instead of a generic failure.
enum CameraCaptureStatus {
  success,
  cancelled,
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
}

class CameraCaptureOutcome {
  const CameraCaptureOutcome._(this.status, this.file);

  const CameraCaptureOutcome.success(File file)
    : this._(CameraCaptureStatus.success, file);

  const CameraCaptureOutcome.cancelled()
    : this._(CameraCaptureStatus.cancelled, null);

  const CameraCaptureOutcome.permissionDenied()
    : this._(CameraCaptureStatus.permissionDenied, null);

  const CameraCaptureOutcome.permissionPermanentlyDenied()
    : this._(CameraCaptureStatus.permissionPermanentlyDenied, null);

  const CameraCaptureOutcome.unavailable()
    : this._(CameraCaptureStatus.unavailable, null);

  final CameraCaptureStatus status;

  /// Only non-null when [status] is [CameraCaptureStatus.success].
  final File? file;
}
