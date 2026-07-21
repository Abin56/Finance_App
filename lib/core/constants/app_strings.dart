/// Static, non-localized copy used across the app.
/// (A localization layer can replace this later without touching call sites
/// if values are always referenced through [AppStrings].)
abstract class AppStrings {
  AppStrings._();

  static const String appName = 'FlowFi';
  static const String tagline = 'Your Money. Clearly Managed.';
}
