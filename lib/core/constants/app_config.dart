/// App-wide tunables that aren't visual (see [AppSizes] for those).
abstract class AppConfig {
  AppConfig._();

  /// How long a soft-deleted record stays in trash before
  /// [HiveCrudRepository.purgeExpiredTrash] removes it for good.
  /// Becomes user-configurable from Settings → Backup in Milestone 8;
  /// until then every feature's trash uses this single default so the
  /// behavior is at least consistent and already wired up.
  static const Duration trashRetention = Duration(days: 30);
}
