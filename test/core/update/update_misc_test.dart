import 'package:finance_app/core/update/data/android_release_client.dart';
import 'package:finance_app/core/update/data/app_update_platform.dart';
import 'package:finance_app/core/update/data/android_update_downloader.dart';
import 'package:finance_app/core/update/data/update_reminder_store.dart';
import 'package:finance_app/core/update/domain/android_release_info.dart';
import 'package:finance_app/core/update/domain/android_update_override.dart';
import 'package:finance_app/core/update/domain/android_update_status.dart';
import 'package:finance_app/core/update/providers/android_update_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _manifest({int code = 6, Object? pkg = 'com.flowfi.app'}) => {
      'version': '1.0.5',
      'versionCode': code,
      'sha256': 'c' * 64,
      'sizeBytes': 1000,
      'file': 'flowfi-android-1.0.5.apk',
      'packageName': ?pkg,
    };

class _SupportedPlatform extends AppUpdatePlatform {
  const _SupportedPlatform(this.supported);
  final bool supported;
  @override
  Future<bool> isSelfUpdateSupported() async => supported;
}

void main() {
  group('manifest parsing', () {
    test('accepts the published shape, with or without packageName', () {
      expect(AndroidReleaseInfo.parse(_manifest(), origin: 'https://x.y'), isNotNull);
      expect(AndroidReleaseInfo.parse(_manifest(pkg: null), origin: 'https://x.y'), isNotNull);
    });

    test('rejects a manifest for another package', () {
      expect(
        AndroidReleaseInfo.parse(_manifest(pkg: 'com.evil.app'), origin: 'https://x.y'),
        isNull,
      );
    });

    test('APK url is always same-origin next to the manifest', () {
      final r = AndroidReleaseInfo.parse(_manifest(), origin: 'https://flowfi.web.app/')!;
      expect(r.url, 'https://flowfi.web.app/downloads/flowfi-android-1.0.5.apk');
    });

    test('path-traversal file names are rejected', () {
      final m = _manifest()..['file'] = '../../evil.apk';
      expect(AndroidReleaseInfo.parse(m, origin: 'https://x.y'), isNull);
    });
  });

  group('minimum supported floor', () {
    AndroidReleaseInfo release(int? floor) => AndroidReleaseInfo(
          version: '1.0.5',
          versionCode: 6,
          sha256: 'a' * 64,
          sizeBytes: 1,
          url: 'https://x/y.apk',
          mandatory: false,
          minSupportedVersionCode: floor,
        );

    test('override can raise but never lower the release floor', () {
      // Release says builds < 5 are unsupported; a lower override must not
      // silently un-force an installed build 4.
      final s = computeAndroidUpdateStatus(
        release: release(5),
        override: const AndroidUpdateOverride(minSupportedVersionCode: 2),
        installedVersionCode: 4,
      );
      expect(s, isA<UpdateMandatory>());
    });
  });

  group('reminder store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('Later snoozes that release for 24h; a newer release prompts again', () async {
      final store = UpdateReminderStore(await SharedPreferences.getInstance());
      final t0 = DateTime(2026, 11, 19, 10);
      expect(store.isSnoozed(6, now: t0), isFalse);
      await store.snooze(6, now: t0);
      expect(store.isSnoozed(6, now: t0.add(const Duration(hours: 23))), isTrue);
      expect(store.isSnoozed(6, now: t0.add(const Duration(hours: 25))), isFalse);
      expect(store.isSnoozed(7, now: t0), isFalse);
    });
  });

  group('release controller', () {
    ProviderContainer make(http.Client client, {bool supported = true}) {
      return ProviderContainer(overrides: [
        appUpdatePlatformProvider.overrideWithValue(_SupportedPlatform(supported)),
        androidReleaseClientProvider.overrideWithValue(
          AndroidReleaseClient(client: client, origin: 'https://flowfi.web.app'),
        ),
      ]);
    }

    test('unsupported build (play flavor / non-Android) never fetches', () async {
      var calls = 0;
      final c = make(MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }), supported: false);
      addTearDown(c.dispose);
      expect(await c.read(androidReleaseInfoProvider.future), isNull);
      expect(await c.read(androidReleaseInfoProvider.notifier).refresh(force: true), isTrue);
      expect(calls, 0);
    });

    test('a failed refresh keeps the last good manifest', () async {
      var fail = false;
      final c = make(MockClient((_) async {
        if (fail) return http.Response('boom', 500);
        return http.Response(
          '{"version":"1.0.5","versionCode":6,"sha256":"${'c' * 64}",'
          '"sizeBytes":1000,"file":"flowfi-android-1.0.5.apk"}',
          200,
        );
      }));
      addTearDown(c.dispose);

      expect((await c.read(androidReleaseInfoProvider.future))!.versionCode, 6);
      fail = true;
      final ok = await c.read(androidReleaseInfoProvider.notifier).refresh(force: true);
      expect(ok, isFalse);
      expect(c.read(androidReleaseInfoProvider).value!.versionCode, 6);
    });

    test('refresh is throttled unless forced', () async {
      var calls = 0;
      final c = make(MockClient((_) async {
        calls++;
        return http.Response('nope', 404);
      }));
      addTearDown(c.dispose);
      await c.read(androidReleaseInfoProvider.future);
      expect(calls, 1);
      await c.read(androidReleaseInfoProvider.notifier).refresh();
      expect(calls, 1);
      await c.read(androidReleaseInfoProvider.notifier).refresh(force: true);
      expect(calls, 2);
    });
  });
}
