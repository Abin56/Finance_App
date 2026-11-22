/// Operator-only emergency override for the in-app update check — mirrors
/// `appConfig/androidUpdate` in Firestore (read-only for clients; written
/// only via the Admin SDK/console, same convention as
/// `smsSyncControl/global` — see `sms_background_upload_switch.dart`). Lets
/// ops force-mandatory or raise the minimum supported build without a new
/// hosting deploy. Deliberately carries no URL or hash: the APK itself always
/// comes from [AndroidReleaseInfo].
class AndroidUpdateOverride {
  const AndroidUpdateOverride({this.mandatory, this.minSupportedVersionCode});

  final bool? mandatory;
  final int? minSupportedVersionCode;

  static AndroidUpdateOverride? parse(Map<String, Object?>? data) {
    if (data == null) return null;
    final mandatory = data['mandatory'];
    final minSupportedVersionCode = data['minSupportedVersionCode'];
    return AndroidUpdateOverride(
      mandatory: mandatory is bool ? mandatory : null,
      minSupportedVersionCode:
          minSupportedVersionCode is int && minSupportedVersionCode >= 1
          ? minSupportedVersionCode
          : null,
    );
  }
}
