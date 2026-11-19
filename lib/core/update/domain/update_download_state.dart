/// Why a download/verify/install attempt stopped before finishing.
enum UpdateFailureReason {
  /// Download couldn't complete (offline, timed out, server error).
  network,

  /// The downloaded file's SHA-256 didn't match the signed manifest — never
  /// installed. Could mean a corrupted download or a tampered mirror; either
  /// way, retrying the download is the right next step.
  hashMismatch,

  /// Android's "install unknown apps" permission was denied for FlowFi.
  permissionDenied,

  /// The system installer itself refused the file — the most likely real
  /// cause on affected devices is Play Protect's enhanced fraud protection
  /// blocking an internet-sideloaded APK, the same block already seen on
  /// first installs (see `docs/sms-sync-pairing.md`). There is no in-app fix
  /// for this; the user has to fall back to the browser/QR download.
  installerBlocked,

  /// The device ran out of storage while saving the APK.
  storage,

  unknown,
}

/// State machine for one download-verify-install attempt, driven by
/// `AndroidUpdateDownloadController`.
sealed class UpdateDownloadState {
  const UpdateDownloadState();
}

class UpdateDownloadIdle extends UpdateDownloadState {
  const UpdateDownloadIdle();
}

class UpdateDownloading extends UpdateDownloadState {
  const UpdateDownloading({
    required this.receivedBytes,
    this.totalBytes,
    this.resumed = false,
  });

  /// True when this attempt continued a previous partial download.
  final bool resumed;
  final int receivedBytes;
  final int? totalBytes;

  double? get progress =>
      totalBytes == null || totalBytes == 0 ? null : receivedBytes / totalBytes!;
}

class UpdateVerifying extends UpdateDownloadState {
  const UpdateVerifying();
}

/// Handed off to Android's system installer UI. FlowFi has no reliable way
/// to learn whether the user actually completed the install from here —
/// Android doesn't report that back — so this is the attempt's terminal
/// success state; the app simply keeps running until the OS replaces it.
class UpdateInstallRequested extends UpdateDownloadState {
  const UpdateInstallRequested();
}

class UpdateFailed extends UpdateDownloadState {
  const UpdateFailed(this.reason, {this.message});
  final UpdateFailureReason reason;
  final String? message;
}
