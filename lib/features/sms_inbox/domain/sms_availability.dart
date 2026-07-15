/// Single source of truth the SMS Inbox permission gate switches on.
enum SmsAvailability {
  /// Permission granted — the inbox can be scanned.
  granted,

  /// Permission asked before and denied; the OS will show its own dialog
  /// again if we ask.
  denied,

  /// Denied "don't ask again" (or denied twice on iOS-style platforms) —
  /// only `openAppSettings()` can recover this.
  permanentlyDenied,

  /// Not Android — there is no public SMS-reading API on this platform.
  unsupportedPlatform,

  /// Android, but we have never asked the user yet — show the explanation
  /// copy before the OS permission dialog appears.
  notRequestedYet,
}
