import 'android_release_info.dart';
import 'android_update_override.dart';

/// Whether the installed app should prompt for an update, and whether that
/// prompt is skippable. A sealed class (not a bool/enum pair) so every call
/// site is forced to handle all three outcomes explicitly via `switch`.
sealed class AndroidUpdateStatus {
  const AndroidUpdateStatus();
}

/// Nothing to offer — either no release is published, the published release
/// is not newer than what's installed, or the check couldn't complete (no
/// network, parse failure, etc. — failures are deliberately treated the same
/// as "nothing to offer" rather than blocking the app).
class UpdateNotAvailable extends AndroidUpdateStatus {
  const UpdateNotAvailable();
}

/// A newer build exists; the user can install it now or keep using the app.
class UpdateOptional extends AndroidUpdateStatus {
  const UpdateOptional(this.release);
  final AndroidReleaseInfo release;
}

/// A newer build exists and must be installed before the app can be used —
/// either the release itself was published with `--mandatory`, an operator
/// override forced it, or the installed build fell below the minimum
/// supported versionCode.
class UpdateMandatory extends AndroidUpdateStatus {
  const UpdateMandatory(this.release);
  final AndroidReleaseInfo release;
}

/// Pure merge of the signed release manifest, the optional Firestore
/// override, and the installed build's versionCode. No I/O, no Firebase —
/// exercised directly by `android_update_status_test.dart`.
AndroidUpdateStatus computeAndroidUpdateStatus({
  required AndroidReleaseInfo? release,
  required AndroidUpdateOverride? override,
  required int installedVersionCode,
}) {
  if (release == null) return const UpdateNotAvailable();
  if (release.versionCode <= installedVersionCode) {
    return const UpdateNotAvailable();
  }

  final minSupportedVersionCode =
      override?.minSupportedVersionCode ?? release.minSupportedVersionCode;
  final belowFloor = minSupportedVersionCode != null &&
      installedVersionCode < minSupportedVersionCode;
  final isMandatory =
      release.mandatory || (override?.mandatory ?? false) || belowFloor;

  return isMandatory ? UpdateMandatory(release) : UpdateOptional(release);
}
