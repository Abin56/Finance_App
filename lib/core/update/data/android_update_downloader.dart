import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/android_release_info.dart';
import '../domain/update_download_state.dart';
import 'app_update_platform.dart';

const String _updatesSubdir = 'updates';
const String _apkMime = 'application/vnd.android.package-archive';

/// Time to the first response byte, and the longest silence tolerated between
/// two chunks of an in-flight download (a stalled connection fails over to
/// "Try again", which resumes instead of restarting).
const Duration _connectTimeout = Duration(seconds: 20);
const Duration _stallTimeout = Duration(seconds: 30);

/// Outcome of handing the verified APK to Android's package installer.
enum InstallHandoff { started, permissionDenied, blocked }

class InstallHandoffResult {
  const InstallHandoffResult(this.handoff, {this.message});
  final InstallHandoff handoff;
  final String? message;
}

typedef ApkInstaller = Future<InstallHandoffResult> Function(String path);

/// Default installer: Android's system package installer via an ACTION_VIEW
/// intent (the user always confirms — there is no silent install).
Future<InstallHandoffResult> openWithSystemInstaller(String path) async {
  final result = await OpenFilex.open(path, type: _apkMime);
  switch (result.type) {
    case ResultType.done:
      return const InstallHandoffResult(InstallHandoff.started);
    case ResultType.permissionDenied:
      return const InstallHandoffResult(InstallHandoff.permissionDenied);
    case ResultType.noAppToOpen:
    case ResultType.fileNotFound:
    case ResultType.error:
      // Play Protect / OEM blocks surface as a generic installer error —
      // Android exposes no way to tell "blocked" from any other failure.
      return InstallHandoffResult(
        InstallHandoff.blocked,
        message: result.message,
      );
  }
}

/// The cache directory the APK is downloaded into. Overridable for tests.
final updatesDirectoryResolverProvider =
    Provider<Future<Directory> Function()>((ref) {
  return () async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/$_updatesSubdir',
    );
    await dir.create(recursive: true);
    return dir;
  };
});

final updateHttpClientFactoryProvider =
    Provider<http.Client Function()>((ref) => http.Client.new);

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => openWithSystemInstaller,
);

final appUpdatePlatformProvider = Provider<AppUpdatePlatform>(
  (ref) => const AppUpdatePlatform(),
);

/// Downloads the published APK, verifies its size and SHA-256 against the
/// published manifest, then hands it to Android's system installer.
///
/// - **Resume**: a partial `.part` file from an earlier failed attempt is
///   continued with an HTTP Range request (falling back to a fresh download
///   if the server answers 200). The final SHA-256 check still covers the
///   whole file, so a bad resume can never reach the installer.
/// - **Retry**: an already-downloaded, verified APK is reused, so "Try again"
///   after a permission or installer problem never re-downloads 140 MB.
/// - **Cancel**: [cancel] aborts the transfer and removes the partial file.
class AndroidUpdateDownloadController extends Notifier<UpdateDownloadState> {
  http.Client? _client;
  bool _cancelled = false;
  bool _busy = false;

  @override
  UpdateDownloadState build() => const UpdateDownloadIdle();

  bool get isBusy => _busy;

  Future<void> start(AndroidReleaseInfo release) async {
    if (_busy) return;
    _busy = true;
    _cancelled = false;
    try {
      await _run(release);
    } finally {
      _busy = false;
      _client = null;
    }
  }

  /// Aborts an in-flight download and discards the partial file.
  void cancel() {
    if (!_busy) return;
    _cancelled = true;
    _client?.close();
  }

  void reset() {
    if (_busy) return;
    state = const UpdateDownloadIdle();
  }

  Future<void> _run(AndroidReleaseInfo release) async {
    final platform = ref.read(appUpdatePlatformProvider);

    // Ask for the install permission BEFORE spending 140 MB of data on a file
    // Android would then refuse to open.
    if (!await platform.canInstallPackages()) {
      state = const UpdateFailed(UpdateFailureReason.permissionDenied);
      return;
    }

    final dir = await ref.read(updatesDirectoryResolverProvider)();
    final finalFile = File('${dir.path}/flowfi-android-${release.version}.apk');
    final partFile = File('${finalFile.path}.part');
    await _deleteOtherFiles(
      dir,
      keep: {_baseName(finalFile.path), _baseName(partFile.path)},
    );

    try {
      var ready = false;
      if (await finalFile.exists()) {
        state = const UpdateVerifying();
        ready = await _verify(finalFile, release);
        if (!ready) await _safeDelete(finalFile);
      }

      if (!ready) {
        state = const UpdateDownloading(receivedBytes: 0);
        await _download(release, partFile);
        if (_cancelled) throw const _Cancelled();
        await partFile.rename(finalFile.path);

        state = const UpdateVerifying();
        if (!await _verify(finalFile, release)) {
          await _safeDelete(finalFile);
          state = const UpdateFailed(UpdateFailureReason.hashMismatch);
          return;
        }
      }
    } on _Cancelled {
      await _safeDelete(partFile);
      state = const UpdateDownloadIdle();
      return;
    } catch (error) {
      if (_cancelled) {
        await _safeDelete(partFile);
        state = const UpdateDownloadIdle();
        return;
      }
      state = UpdateFailed(_classify(error));
      return;
    }

    final handoff = await ref.read(apkInstallerProvider)(finalFile.path);
    state = switch (handoff.handoff) {
      InstallHandoff.started => const UpdateInstallRequested(),
      InstallHandoff.permissionDenied =>
        const UpdateFailed(UpdateFailureReason.permissionDenied),
      InstallHandoff.blocked => UpdateFailed(
          UpdateFailureReason.installerBlocked,
          message: handoff.message,
        ),
    };
  }

  Future<void> _download(AndroidReleaseInfo release, File part) async {
    var existing = await part.exists() ? await part.length() : 0;
    if (existing >= release.sizeBytes) {
      await _safeDelete(part);
      existing = 0;
    }

    final client = _client = ref.read(updateHttpClientFactoryProvider)();
    try {
      final request = http.Request('GET', Uri.parse(release.url));
      if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
      final response = await client.send(request).timeout(_connectTimeout);

      final bool append;
      if (response.statusCode == 206 && existing > 0) {
        append = true;
      } else if (response.statusCode == 200) {
        append = false;
        existing = 0;
      } else {
        throw HttpException('Unexpected status ${response.statusCode}');
      }

      final sink =
          part.openWrite(mode: append ? FileMode.append : FileMode.write);
      // The manifest's size is the authority for progress: it is what the
      // hash check expects, and it is correct even for a ranged response.
      final total = release.sizeBytes;
      var received = existing;
      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
      state = UpdateDownloading(
        receivedBytes: received,
        totalBytes: total,
        resumed: existing > 0,
      );
      try {
        await for (final chunk in response.stream.timeout(_stallTimeout)) {
          if (_cancelled) throw const _Cancelled();
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastEmit) >= const Duration(milliseconds: 150)) {
            lastEmit = now;
            state = UpdateDownloading(
              receivedBytes: received > total ? total : received,
              totalBytes: total,
              resumed: existing > 0,
            );
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  /// Size, then SHA-256, both against the published manifest. The hash is
  /// computed in a background isolate so a 140 MB file never janks the UI.
  Future<bool> _verify(File file, AndroidReleaseInfo release) async {
    if (await file.length() != release.sizeBytes) return false;
    final path = file.path;
    final digest = await Isolate.run(
      () async => (await sha256.bind(File(path).openRead()).first).toString(),
    );
    return digest.toLowerCase() == release.sha256.toLowerCase();
  }

  UpdateFailureReason _classify(Object error) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      final text = '${error.message} ${error.osError?.message}'.toLowerCase();
      if (code == 28 || text.contains('no space')) {
        return UpdateFailureReason.storage;
      }
      return UpdateFailureReason.unknown;
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is http.ClientException) {
      return UpdateFailureReason.network;
    }
    return UpdateFailureReason.unknown;
  }

  /// Removes stale downloads (an older release's APK/partial) so at most one
  /// release's files ever sit in the cache.
  Future<void> _deleteOtherFiles(
    Directory dir, {
    required Set<String> keep,
  }) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File && !keep.contains(_baseName(entity.path))) {
          await _safeDelete(entity);
        }
      }
    } catch (_) {}
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Deletes the whole updates cache — called once the installed build has
/// caught up with the published one (the ~140 MB APK is no longer needed).
Future<void> clearUpdatesCache(Future<Directory> Function() resolver) async {
  try {
    final dir = await resolver();
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {}
}

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

class _Cancelled implements Exception {
  const _Cancelled();
}

final androidUpdateDownloadProvider =
    NotifierProvider<AndroidUpdateDownloadController, UpdateDownloadState>(
  AndroidUpdateDownloadController.new,
);
