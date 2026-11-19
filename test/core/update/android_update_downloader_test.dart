import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:finance_app/core/update/data/android_update_downloader.dart';
import 'package:finance_app/core/update/data/app_update_platform.dart';
import 'package:finance_app/core/update/domain/android_release_info.dart';
import 'package:finance_app/core/update/domain/update_download_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform extends AppUpdatePlatform {
  _FakePlatform();
  bool canInstall = true;
  @override
  Future<bool> canInstallPackages() async => canInstall;
}

/// Local HTTP server standing in for Firebase Hosting: serves one APK with
/// Range support, and can cut the first connection short to simulate a drop.
class _ApkServer {
  _ApkServer(this.bytes);

  final Uint8List bytes;
  late final HttpServer server;
  int? cutFirstResponseAt;
  bool ignoreRange = false;
  final requests = <String?>[]; // Range header of each request
  int statusOverride = 0;
  Duration? chunkDelay;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.headers.value('range'));
      if (statusOverride != 0) {
        req.response.statusCode = statusOverride;
        await req.response.close();
        return;
      }
      var start = 0;
      final range = req.headers.value('range');
      if (range != null && !ignoreRange) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
        req.response.headers.set(
          'content-range',
          'bytes $start-${bytes.length - 1}/${bytes.length}',
        );
      }
      final body = bytes.sublist(start);
      req.response.contentLength = body.length;
      final cut = (requests.length == 1) ? cutFirstResponseAt : null;
      try {
        if (chunkDelay != null) {
          for (var i = 0; i < body.length; i += 64 * 1024) {
            req.response.add(body.sublist(i, min(i + 64 * 1024, body.length)));
            await req.response.flush();
            await Future<void>.delayed(chunkDelay!);
          }
        } else if (cut != null) {
          // Headers (with the full Content-Length) are written by detach,
          // then only part of the body is sent before the socket dies.
          final socket = await req.response.detachSocket();
          socket.add(body.sublist(0, cut));
          await socket.flush();
          socket.destroy();
          return;
        } else {
          req.response.add(body);
        }
        await req.response.close();
      } catch (_) {}
    });
  }

  String get url => 'http://127.0.0.1:${server.port}/flowfi-android-1.0.5.apk';
  Future<void> stop() => server.close(force: true);
}

AndroidReleaseInfo _release(Uint8List bytes, String url, {String? sha}) {
  return AndroidReleaseInfo(
    version: '1.0.5',
    versionCode: 6,
    sha256: sha ?? sha256.convert(bytes).toString(),
    sizeBytes: bytes.length,
    url: url,
    mandatory: false,
  );
}

void main() {
  late Directory tmp;
  late Uint8List bytes;
  late _ApkServer server;
  late List<String> installed;
  late _FakePlatform platform;
  late ProviderContainer container;

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        updatesDirectoryResolverProvider.overrideWithValue(() async {
          final dir = Directory('${tmp.path}/updates');
          await dir.create(recursive: true);
          return dir;
        }),
        appUpdatePlatformProvider.overrideWithValue(platform),
        apkInstallerProvider.overrideWithValue((path) async {
          installed.add(path);
          return const InstallHandoffResult(InstallHandoff.started);
        }),
      ],
    );
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('flowfi_update_test_');
    final rng = Random(7);
    bytes = Uint8List.fromList(
      List<int>.generate(2 * 1024 * 1024 + 123, (_) => rng.nextInt(256)),
    );
    server = _ApkServer(bytes);
    await server.start();
    installed = [];
    platform = _FakePlatform();
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    await server.stop();
    await tmp.delete(recursive: true);
  });

  AndroidUpdateDownloadController controller() =>
      container.read(androidUpdateDownloadProvider.notifier);
  UpdateDownloadState state() => container.read(androidUpdateDownloadProvider);

  test('downloads, verifies, and hands the verified APK to the installer', () async {
    final release = _release(bytes, server.url);
    await controller().start(release);

    expect(state(), isA<UpdateInstallRequested>());
    expect(installed, hasLength(1));
    expect(await File(installed.single).readAsBytes(), bytes);
    expect(File('${installed.single}.part').existsSync(), isFalse);
  });

  test('hash mismatch is never installed and the file is discarded', () async {
    final release = _release(bytes, server.url, sha: 'b' * 64);
    await controller().start(release);

    expect(state(), isA<UpdateFailed>());
    expect((state() as UpdateFailed).reason, UpdateFailureReason.hashMismatch);
    expect(installed, isEmpty);
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
  });

  test('size mismatch is rejected even before hashing', () async {
    final release = AndroidReleaseInfo(
      version: '1.0.5',
      versionCode: 6,
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length + 10,
      url: server.url,
      mandatory: false,
    );
    await controller().start(release);
    expect((state() as UpdateFailed).reason, UpdateFailureReason.hashMismatch);
    expect(installed, isEmpty);
  });

  test('connection drop → network failure, then Try again RESUMES via Range', () async {
    server.cutFirstResponseAt = 600 * 1024;
    final release = _release(bytes, server.url);

    await controller().start(release);
    expect((state() as UpdateFailed).reason, UpdateFailureReason.network);
    final part = File('${tmp.path}/updates/flowfi-android-1.0.5.apk.part');
    expect(part.existsSync(), isTrue);
    final partial = part.lengthSync();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(bytes.length));

    controller().reset();
    await controller().start(release);

    expect(state(), isA<UpdateInstallRequested>());
    expect(server.requests.last, 'bytes=$partial-');
    expect(await File(installed.single).readAsBytes(), bytes);
  });

  test('server ignoring Range (200) restarts cleanly and still verifies', () async {
    server.cutFirstResponseAt = 400 * 1024;
    server.ignoreRange = true;
    final release = _release(bytes, server.url);

    await controller().start(release);
    controller().reset();
    await controller().start(release);

    expect(state(), isA<UpdateInstallRequested>());
    expect(await File(installed.single).readAsBytes(), bytes);
  });

  test('HTTP error status → network failure, nothing installed', () async {
    server.statusOverride = 503;
    await controller().start(_release(bytes, server.url));
    expect((state() as UpdateFailed).reason, UpdateFailureReason.network);
    expect(installed, isEmpty);
  });

  test('install permission missing → fails BEFORE any download', () async {
    platform.canInstall = false;
    await controller().start(_release(bytes, server.url));

    expect((state() as UpdateFailed).reason, UpdateFailureReason.permissionDenied);
    expect(server.requests, isEmpty);

    // Granted later: retry succeeds.
    platform.canInstall = true;
    controller().reset();
    await controller().start(_release(bytes, server.url));
    expect(state(), isA<UpdateInstallRequested>());
  });

  test('"Install again" reuses the verified APK without re-downloading', () async {
    final release = _release(bytes, server.url);
    await controller().start(release);
    expect(server.requests, hasLength(1));

    await controller().start(release);
    expect(server.requests, hasLength(1));
    expect(installed, hasLength(2));
    expect(state(), isA<UpdateInstallRequested>());
  });

  test('a corrupted cached APK is discarded and re-downloaded', () async {
    final release = _release(bytes, server.url);
    await controller().start(release);
    await File(installed.single).writeAsBytes([1, 2, 3]);

    await controller().start(release);
    expect(server.requests, hasLength(2));
    expect(await File(installed.last).readAsBytes(), bytes);
  });

  test('cancel mid-download returns to idle and removes the partial file', () async {
    server.chunkDelay = const Duration(milliseconds: 40);
    final release = _release(bytes, server.url);

    final running = controller().start(release);
    // Wait until bytes are actually flowing.
    while (state() is! UpdateDownloading ||
        (state() as UpdateDownloading).receivedBytes == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    controller().cancel();
    await running;

    expect(state(), isA<UpdateDownloadIdle>());
    expect(installed, isEmpty);
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
  });

  test('progress is reported against the manifest size', () async {
    server.chunkDelay = const Duration(milliseconds: 15);
    final release = _release(bytes, server.url);
    final seen = <double>[];
    container.listen<UpdateDownloadState>(androidUpdateDownloadProvider, (_, next) {
      if (next is UpdateDownloading && next.progress != null) {
        seen.add(next.progress!);
      }
    });
    await controller().start(release);

    expect(seen, isNotEmpty);
    expect(seen.every((p) => p >= 0 && p <= 1), isTrue);
    expect(seen.last, greaterThan(0.5));
    // Monotonic.
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('stale files from an older release are removed on the next download', () async {
    final dir = Directory('${tmp.path}/updates')..createSync(recursive: true);
    File('${dir.path}/flowfi-android-1.0.3.apk').writeAsBytesSync([1]);
    await controller().start(_release(bytes, server.url));
    expect(File('${dir.path}/flowfi-android-1.0.3.apk').existsSync(), isFalse);
  });

  test('clearUpdatesCache empties the directory', () async {
    final dir = Directory('${tmp.path}/updates')..createSync(recursive: true);
    File('${dir.path}/x.apk').writeAsBytesSync([1]);
    await clearUpdatesCache(() async => dir);
    expect(dir.listSync(), isEmpty);
  });
}
