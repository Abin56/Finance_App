/// Whether FlowFi is currently exempt from the OS's Doze/App Standby battery
/// restrictions. Matters specifically for [NotificationCaptureListenerService]:
/// an OEM background-freezing policy (e.g. Samsung's "Optimised" battery mode)
/// can silently stop that service's callback from ever running, even though
/// the listener itself stays registered and shows as "enabled" — so a
/// notification-access grant alone doesn't guarantee RCS capture actually
/// works.
enum BatteryOptimizationAvailability {
  /// Exempt — background work (including the notification listener) is
  /// never OS-throttled just for running unattended.
  unrestricted,

  /// Still subject to the OS's default battery restrictions.
  restricted,

  /// Not Android — there is no such restriction to check on this platform.
  unsupportedPlatform,
}
