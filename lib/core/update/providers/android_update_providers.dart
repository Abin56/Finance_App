import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../providers/firebase_providers.dart';
import '../data/android_release_client.dart';
import '../data/android_update_override_repository.dart';
import '../domain/android_release_info.dart';
import '../domain/android_update_override.dart';
import '../domain/android_update_status.dart';

final androidReleaseClientProvider = Provider<AndroidReleaseClient>((ref) {
  return AndroidReleaseClient();
});

/// The published release manifest. Re-fetched once per app launch (a
/// `Provider`, not kept alive across the whole session beyond that) — a
/// stale "update available" prompt for a few minutes is harmless, and this
/// avoids polling Firebase Hosting on every rebuild.
final androidReleaseInfoProvider = FutureProvider<AndroidReleaseInfo?>((ref) {
  return ref.watch(androidReleaseClientProvider).fetchLatest();
});

final androidUpdateOverrideRepositoryProvider =
    Provider<AndroidUpdateOverrideRepository>((ref) {
  return AndroidUpdateOverrideRepository(ref.watch(firestoreProvider));
});

final androidUpdateOverrideProvider =
    StreamProvider<AndroidUpdateOverride?>((ref) {
  return ref.watch(androidUpdateOverrideRepositoryProvider).watch();
});

/// The running app's own versionCode (Android's `android:versionCode`, read
/// via `PackageInfo.buildNumber`) — compared as an integer, never as a
/// semver string, since `scripts/android-release.mjs` already enforces that
/// versionCode is strictly increasing release to release.
final installedVersionCodeProvider = FutureProvider<int?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber);
  } catch (_) {
    return null;
  }
});

/// Fail-open by construction: every input defaults to "nothing new" while
/// loading or on any error, so a flaky network connection or a transient
/// Firestore read failure never shows a stale prompt or — worse — blocks the
/// app behind a mandatory-update screen it can't actually satisfy.
final androidUpdateStatusProvider = Provider<AndroidUpdateStatus>((ref) {
  final installedVersionCode = ref.watch(installedVersionCodeProvider).value;
  if (installedVersionCode == null) return const UpdateNotAvailable();

  return computeAndroidUpdateStatus(
    release: ref.watch(androidReleaseInfoProvider).value,
    override: ref.watch(androidUpdateOverrideProvider).value,
    installedVersionCode: installedVersionCode,
  );
});

/// Read by `app_router.dart`'s redirect gate; `router_refresh_notifier.dart`
/// listens to it so the gate re-evaluates the moment the async check above
/// resolves.
final updateRequiredProvider = Provider<bool>((ref) {
  return ref.watch(androidUpdateStatusProvider) is UpdateMandatory;
});
