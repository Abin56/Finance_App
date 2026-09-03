/// Thrown by `SmsReaderAdapter` instead of leaking `flutter_sms_inbox`'s own
/// `PlatformException` past the adapter boundary, so callers get an actionable
/// message rather than a raw platform-channel error code.
sealed class SmsReadException implements Exception {
  const SmsReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The OS refused the SMS content-provider query for a permission reason —
/// either `READ_SMS` was never granted, was revoked mid-session, or the
/// installed build simply does not declare it (see the `sideload` vs `play`
/// build flavors in `android/app/build.gradle.kts`). Distinct from an empty
/// inbox: this means the read never happened at all.
class SmsPermissionUnavailableException extends SmsReadException {
  const SmsPermissionUnavailableException()
    : super(
        'SMS access was denied by the operating system. Either the installed '
        'app build does not include SMS permission, or it was revoked after '
        'being granted — check Settings > Apps > FlowFi > Permissions, or '
        'reinstall a build with SMS Inbox enabled.',
      );
}

/// The content-provider query itself failed for a non-permission reason
/// (device/OEM restriction, malformed cursor, etc).
class SmsQueryFailedException extends SmsReadException {
  SmsQueryFailedException(String detail)
    : super('Could not read SMS messages: $detail');
}
