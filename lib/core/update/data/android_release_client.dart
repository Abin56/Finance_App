import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/android_release_info.dart';

/// Same origin and manifest path as `ANDROID_RELEASE_MANIFEST_PATH` /
/// `DEFAULT_ORIGIN` in the Flow-Fi-WEB repo's `scripts/android-release.mjs`
/// and `lib/sms-pairing/android-release.ts` — keep all three in sync.
const String androidReleaseOrigin = 'https://flowfi.web.app';
const String _manifestPath = '/downloads/flowfi-android.json';

/// Fetches and parses the published Android release manifest. Every failure
/// mode (offline, timeout, malformed JSON, no release published yet) returns
/// null rather than throwing — the update check is fail-open by design, so a
/// broken network connection never blocks the app.
class AndroidReleaseClient {
  AndroidReleaseClient({http.Client? client, this.origin = androidReleaseOrigin})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String origin;

  Future<AndroidReleaseInfo?> fetchLatest() async {
    try {
      final response = await _client
          .get(Uri.parse('$origin$_manifestPath'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      return AndroidReleaseInfo.parse(body, origin: origin);
    } catch (_) {
      return null;
    }
  }
}
