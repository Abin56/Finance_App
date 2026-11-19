/// The published Android sideload build, mirroring
/// `flowfi-android.json` on FlowFi Web's own Firebase Hosting (written by
/// `scripts/android-release.mjs` in the Flow-Fi-WEB repo, which signs off the
/// APK before publishing it: release certificate, package id, SHA-256). This
/// is the single source of truth for the download URL and hash — nothing in
/// this app ever installs a file whose hash doesn't match what's here.
class AndroidReleaseInfo {
  const AndroidReleaseInfo({
    required this.version,
    required this.versionCode,
    required this.sha256,
    required this.sizeBytes,
    required this.url,
    required this.mandatory,
    this.releaseNotes,
    this.minSupportedVersionCode,
  });

  final String version;
  final int versionCode;

  /// Lower-case hex SHA-256 of the APK file, verified again on-device after
  /// download, before the installer is ever invoked.
  final String sha256;
  final int sizeBytes;

  /// Absolute HTTPS URL of the APK, resolved next to the manifest on the
  /// same origin — never an arbitrary host.
  final String url;

  /// True when this specific release was prepared with `--mandatory`.
  final bool mandatory;
  final String? releaseNotes;

  /// Installs with a lower versionCode than this are treated as mandatory,
  /// even when [mandatory] itself is false.
  final int? minSupportedVersionCode;

  static final RegExp _versionPattern = RegExp(r'^[0-9A-Za-z.+_-]{1,40}$');
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _safeFile = RegExp(
    r'^flowfi-android(?:-[0-9A-Za-z.+_-]{1,40})?\.apk$',
  );

  /// Returns null for anything that isn't a complete, well-formed manifest —
  /// callers then simply treat no release as published, the same fail-open
  /// behavior as a network error. Mirrors
  /// `lib/sms-pairing/android-release.ts`'s `parseAndroidRelease` in the web
  /// repo; keep the two in sync.
  static AndroidReleaseInfo? parse(Object? raw, {required String origin}) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final versionCode = raw['versionCode'];
    final sha256 = raw['sha256'];
    final sizeBytes = raw['sizeBytes'];
    final file = raw['file'];
    if (version is! String || !_versionPattern.hasMatch(version)) return null;
    if (versionCode is! int || versionCode < 1) return null;
    if (sha256 is! String || !_sha256Pattern.hasMatch(sha256)) return null;
    if (sizeBytes is! num || sizeBytes <= 0) return null;
    if (file is! String || !_safeFile.hasMatch(file)) return null;

    final mandatory = raw['mandatory'];
    final releaseNotes = raw['releaseNotes'];
    final minSupportedVersionCode = raw['minSupportedVersionCode'];
    return AndroidReleaseInfo(
      version: version,
      versionCode: versionCode,
      sha256: sha256,
      sizeBytes: sizeBytes.toInt(),
      url: '${origin.replaceFirst(RegExp(r'/+$'), '')}/downloads/$file',
      mandatory: mandatory == true,
      releaseNotes: releaseNotes is String && releaseNotes.isNotEmpty
          ? releaseNotes
          : null,
      minSupportedVersionCode: minSupportedVersionCode is int &&
              minSupportedVersionCode >= 1
          ? minSupportedVersionCode
          : null,
    );
  }
}
