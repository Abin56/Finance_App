/// Parsing for the SMS Sync pairing link FlowFi Web encodes in its QR code,
/// and an in-memory holder that keeps a scanned token alive while the router's
/// onboarding/sign-in/lock/setup gates redirect elsewhere first.
///
/// Accepted shapes (both carry the one-time token as `t`):
///   * `flowfi://app/pair?t=…` — the custom scheme the web landing page opens;
///   * `https://<any host>/pair/?t=…` — the QR's own web URL, if Android ever
///     routes it here directly.
///
/// The host is deliberately NOT trusted or checked: the token is the only
/// secret, and the pairing Cloud Function only accepts it from the same
/// signed-in account that created it — a link from anywhere else can at worst
/// show "wrong account" or "invalid", never pair this phone to someone else.
library;

final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// The route the pairing screen lives at.
const String kSmsPairingRoutePath = '/pair';

bool isValidSmsPairingToken(String? token) =>
    token != null && _tokenPattern.hasMatch(token);

/// The pairing token in [uri], or null when [uri] isn't a well-formed pairing
/// link. Works on full deep links and on router locations (`/pair?t=…`).
String? smsPairingTokenFromUri(Uri uri) {
  final path = uri.path.endsWith('/') && uri.path.length > 1
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  if (path != kSmsPairingRoutePath) return null;
  if (uri.hasScheme &&
      !const {'flowfi', 'https', 'http'}.contains(uri.scheme)) {
    return null;
  }
  final token = uri.queryParameters['t'];
  return isValidSmsPairingToken(token) ? token : null;
}

/// Keeps one scanned token in memory (never persisted — it is a short-lived
/// secret) until the pairing screen consumes it. Tokens older than [maxAge]
/// are dropped: the web session behind them has expired anyway.
class PendingSmsPairing {
  PendingSmsPairing({
    DateTime Function()? clock,
    this.maxAge = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration maxAge;
  String? _token;
  DateTime? _receivedAt;

  void offer(String token) {
    if (!isValidSmsPairingToken(token)) return;
    _token = token;
    _receivedAt = _clock();
  }

  /// The pending token, if any and still fresh.
  String? get token {
    final at = _receivedAt;
    if (_token == null || at == null) return null;
    if (_clock().difference(at) > maxAge) {
      clear();
      return null;
    }
    return _token;
  }

  bool get hasToken => token != null;

  void clear() {
    _token = null;
    _receivedAt = null;
  }
}
