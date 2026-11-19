import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/android_release_info.dart';
import '../domain/update_download_state.dart';

/// Must match the `<cache-path name="updates" path="updates/">` entry in
/// `android/app/src/main/res/xml/file_paths.xml` — that's what lets the
/// FileProvider declared in AndroidManifest.xml grant the installer a URI
/// into exactly this folder and nothing else in the app's cache.
const String _updatesSubdir = 'updates';

/// Downloads the published APK, verifies its SHA-256 against the signed
/// manifest, then hands it to Android's system installer. Every step that
/// can fail maps to an explicit [UpdateFailureReason] rather than a bare
/// exception, so the UI can show a specific, actionable message — in
/// particular [UpdateFailureReason.installerBlocked] for the known Play
/// Protect risk (see `update_download_state.dart`).
class AndroidUpdateDownloadController extends Notifier<UpdateDownloadState> {
  @override
  UpdateDownloadState build() => const UpdateDownloadIdle();

  Future<void> start(AndroidReleaseInfo release) async {
    state = const UpdateDownloading(receivedBytes: 0);
    File apkFile;
    try {
      apkFile = await _download(release);
    } catch (_) {
      state = const UpdateFailed(UpdateFailureReason.network);
      return;
    }

    state = const UpdateVerifying();
    final matches = await _sha256Matches(apkFile, release.sha256);
    if (!matches) {
      await apkFile.delete().catchError((_) => apkFile);
      state = const UpdateFailed(UpdateFailureReason.hashMismatch);
      return;
    }

    final granted = await _ensureInstallPermission();
    if (!granted) {
      state = const UpdateFailed(UpdateFailureReason.permissionDenied);
      return;
    }

    final result = await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );
    switch (result.type) {
      case ResultType.done:
        state = const UpdateInstallRequested();
      case ResultType.permissionDenied:
        state = const UpdateFailed(UpdateFailureReason.permissionDenied);
      case ResultType.noAppToOpen:
      case ResultType.fileNotFound:
      case ResultType.error:
        // Play Protect and OEM "unknown sources" blocks typically surface
        // here as a generic installer error, not a distinct result type —
        // there's no on-device API that distinguishes "blocked" from "some
        // other installer error", so this is the catch-all the UI treats as
        // the Play-Protect-blocked fallback.
        state = UpdateFailed(
          UpdateFailureReason.installerBlocked,
          message: result.message,
        );
    }
  }

  void reset() => state = const UpdateDownloadIdle();

  Future<File> _download(AndroidReleaseInfo release) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(release.url));
      final response = await client.send(request).timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != 200) {
        throw HttpException('Unexpected status ${response.statusCode}');
      }

      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/$_updatesSubdir',
      );
      await dir.create(recursive: true);
      final file = File('${dir.path}/flowfi-android-${release.version}.apk');
      final sink = file.openWrite();

      var received = 0;
      final totalBytes = response.contentLength ?? release.sizeBytes;
      await response.stream.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
        state = UpdateDownloading(
          receivedBytes: received,
          totalBytes: totalBytes > 0 ? totalBytes : null,
        );
      }).asFuture<void>();
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  Future<bool> _sha256Matches(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedHex.toLowerCase();
  }

  Future<bool> _ensureInstallPermission() async {
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;
    final result = await Permission.requestInstallPackages.request();
    return result.isGranted;
  }
}

final androidUpdateDownloadProvider =
    NotifierProvider<AndroidUpdateDownloadController, UpdateDownloadState>(
  AndroidUpdateDownloadController.new,
);
