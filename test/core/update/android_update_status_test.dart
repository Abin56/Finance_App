import 'package:finance_app/core/update/domain/android_release_info.dart';
import 'package:finance_app/core/update/domain/android_update_override.dart';
import 'package:finance_app/core/update/domain/android_update_status.dart';
import 'package:flutter_test/flutter_test.dart';

AndroidReleaseInfo _release({
  int versionCode = 5,
  bool mandatory = false,
  int? minSupportedVersionCode,
}) {
  return AndroidReleaseInfo(
    version: '1.1.0',
    versionCode: versionCode,
    sha256: 'a' * 64,
    sizeBytes: 90 * 1024 * 1024,
    url: 'https://flowfi.web.app/downloads/flowfi-android.apk',
    mandatory: mandatory,
    minSupportedVersionCode: minSupportedVersionCode,
  );
}

void main() {
  group('computeAndroidUpdateStatus', () {
    test('no release published → not available', () {
      final status = computeAndroidUpdateStatus(
        release: null,
        override: null,
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateNotAvailable>());
    });

    test('published release is not newer than installed → not available', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 3),
        override: null,
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateNotAvailable>());
    });

    test('newer release, not flagged mandatory → optional', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 5),
        override: null,
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateOptional>());
    });

    test('release itself published with --mandatory → mandatory', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 5, mandatory: true),
        override: null,
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateMandatory>());
    });

    test('operator override forces mandatory on an otherwise-optional release', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 5),
        override: const AndroidUpdateOverride(mandatory: true),
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateMandatory>());
    });

    test('installed build below the release\'s own minSupportedVersionCode → mandatory', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 5, minSupportedVersionCode: 4),
        override: null,
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateMandatory>());
    });

    test('operator override raises the minimum supported versionCode', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 5),
        override: const AndroidUpdateOverride(minSupportedVersionCode: 4),
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateMandatory>());
    });

    test('installed build already meets the minimum supported versionCode → optional', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 5, minSupportedVersionCode: 4),
        override: null,
        installedVersionCode: 4,
      );
      expect(status, isA<UpdateOptional>());
    });

    test('override with no fields set behaves exactly like no override doc', () {
      final status = computeAndroidUpdateStatus(
        release: _release(versionCode: 5),
        override: const AndroidUpdateOverride(),
        installedVersionCode: 3,
      );
      expect(status, isA<UpdateOptional>());
    });
  });

  group('AndroidReleaseInfo.parse', () {
    const origin = 'https://flowfi.web.app';
    final valid = {
      'version': '1.1.0',
      'versionCode': 5,
      'sha256': 'a' * 64,
      'sizeBytes': 90 * 1024 * 1024,
      'file': 'flowfi-android-1.1.0.apk',
    };

    test('parses a minimal, well-formed manifest', () {
      final release = AndroidReleaseInfo.parse(valid, origin: origin);
      expect(release, isNotNull);
      expect(release!.url, '$origin/downloads/flowfi-android-1.1.0.apk');
      expect(release.mandatory, isFalse);
      expect(release.releaseNotes, isNull);
      expect(release.minSupportedVersionCode, isNull);
    });

    test('carries releaseNotes, mandatory and minSupportedVersionCode when present', () {
      final release = AndroidReleaseInfo.parse({
        ...valid,
        'releaseNotes': 'Bug fixes',
        'mandatory': true,
        'minSupportedVersionCode': 3,
      }, origin: origin);
      expect(release!.releaseNotes, 'Bug fixes');
      expect(release.mandatory, isTrue);
      expect(release.minSupportedVersionCode, 3);
    });

    test('rejects a malformed manifest instead of throwing', () {
      expect(AndroidReleaseInfo.parse(null, origin: origin), isNull);
      expect(
        AndroidReleaseInfo.parse({...valid, 'sha256': 'not-hex'}, origin: origin),
        isNull,
      );
      expect(
        AndroidReleaseInfo.parse({...valid, 'file': '../flowfi-android.apk'}, origin: origin),
        isNull,
      );
      expect(
        AndroidReleaseInfo.parse({...valid, 'versionCode': 0}, origin: origin),
        isNull,
      );
    });

    test('treats a malformed minSupportedVersionCode as absent, not a parse failure', () {
      final release = AndroidReleaseInfo.parse({
        ...valid,
        'minSupportedVersionCode': 0,
      }, origin: origin);
      expect(release, isNotNull);
      expect(release!.minSupportedVersionCode, isNull);
    });
  });
}
