import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/firebase_providers.dart';
import '../data/android_release_client.dart';
import '../data/android_update_downloader.dart';
import '../data/android_update_override_repository.dart';
import '../data/update_reminder_store.dart';
import '../domain/android_release_info.dart';
import '../domain/android_update_override.dart';
import '../domain/android_update_status.dart';

final androidReleaseClientProvider = Provider<AndroidReleaseClient>((ref) {
  return AndroidReleaseClient();
});

/// Whether this build may self-update at all: Android + the `sideload`
/// flavor (the only one whose manifest declares REQUEST_INSTALL_PACKAGES).
/// False while still loading, so nothing is fetched or shown prematurely.
final selfUpdateSupportedProvider = FutureProvider<bool>((ref) {
  return ref.watch(appUpdatePlatformProvider).isSelfUpdateSupported();
});

/// The published release manifest: fetched on launch, then refreshed on app
/// resume (throttled) or on demand. A failed refresh keeps the last good
/// manifest instead of dropping a pending update prompt.
class AndroidReleaseController extends AsyncNotifier<AndroidReleaseInfo?> {
  DateTime? _lastAttempt;
  bool _inFlight = false;

  static const Duration minRefreshInterval = Duration(minutes: 10);

  @override
  Future<AndroidReleaseInfo?> build() async {
    if (!await ref.watch(selfUpdateSupportedProvider.future)) return null;
    _lastAttempt = DateTime.now();
    return ref.read(androidReleaseClientProvider).fetchLatest();
  }

  /// Re-checks the server. Returns false only if the check itself failed
  /// (offline, malformed manifest) — "no newer version" is still true.
  Future<bool> refresh({bool force = false}) async {
    if (_inFlight) return true;
    if (!await ref.read(selfUpdateSupportedProvider.future)) return true;
    final last = _lastAttempt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < minRefreshInterval) {
      return true;
    }
    _inFlight = true;
    _lastAttempt = DateTime.now();
    try {
      final fetched =
          await ref.read(androidReleaseClientProvider).fetchLatest();
      if (fetched == null) return false;
      state = AsyncData(fetched);
      return true;
    } finally {
      _inFlight = false;
    }
  }
}

final androidReleaseInfoProvider =
    AsyncNotifierProvider<AndroidReleaseController, AndroidReleaseInfo?>(
  AndroidReleaseController.new,
);

final androidUpdateOverrideRepositoryProvider =
    Provider<AndroidUpdateOverrideRepository>((ref) {
  return AndroidUpdateOverrideRepository(ref.watch(firestoreProvider));
});

final androidUpdateOverrideProvider =
    StreamProvider<AndroidUpdateOverride?>((ref) {
  return ref.watch(androidUpdateOverrideRepositoryProvider).watch();
});

final installedPackageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return null;
  }
});

/// The running app's own versionCode (`PackageInfo.buildNumber`) — compared
/// as an integer, never as a semver string.
final installedVersionCodeProvider = FutureProvider<int?>((ref) async {
  final info = await ref.watch(installedPackageInfoProvider.future);
  return info == null ? null : int.tryParse(info.buildNumber);
});

final updateReminderStoreProvider = FutureProvider<UpdateReminderStore>((
  ref,
) async {
  return UpdateReminderStore(await SharedPreferences.getInstance());
});

/// Fail-open by construction: every input defaults to "nothing new" while
/// loading or on any error, and a build that can't self-update (Play flavor,
/// non-Android) always reports [UpdateNotAvailable].
final androidUpdateStatusProvider = Provider<AndroidUpdateStatus>((ref) {
  if (ref.watch(selfUpdateSupportedProvider).value != true) {
    return const UpdateNotAvailable();
  }
  final installedVersionCode = ref.watch(installedVersionCodeProvider).value;
  if (installedVersionCode == null) return const UpdateNotAvailable();

  return computeAndroidUpdateStatus(
    release: ref.watch(androidReleaseInfoProvider).value,
    override: ref.watch(androidUpdateOverrideProvider).value,
    installedVersionCode: installedVersionCode,
  );
});

/// Read by `app_router.dart`'s redirect gate; `router_refresh_notifier.dart`
/// listens to it so the gate re-evaluates the moment the async check resolves.
final updateRequiredProvider = Provider<bool>((ref) {
  return ref.watch(androidUpdateStatusProvider) is UpdateMandatory;
});
