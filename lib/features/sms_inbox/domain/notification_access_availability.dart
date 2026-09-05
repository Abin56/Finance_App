/// Single source of truth the notification-capture banner switches on.
/// Mirrors [SmsAvailability]'s shape, but with no `permanentlyDenied` state:
/// there is no OS dialog to permanently deny here, only a manual toggle in
/// system Settings — see `NotificationAccessService`.
enum NotificationAccessAvailability {
  /// Notification access granted — the listener service can capture.
  granted,

  /// Explanation shown before, but access is still off in system Settings.
  denied,

  /// Never shown the explanation yet — show it before deep-linking to
  /// Settings.
  notRequestedYet,

  /// Not Android — there is no notification-listener API on this platform.
  unsupportedPlatform,
}
