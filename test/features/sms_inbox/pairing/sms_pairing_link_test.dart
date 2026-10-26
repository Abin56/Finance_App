import 'package:finance_app/features/sms_inbox/pairing/sms_pairing_link.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_abcde';

void main() {
  group('smsPairingTokenFromUri', () {
    test('reads the custom-scheme deep link the web landing page opens', () {
      expect(
        smsPairingTokenFromUri(Uri.parse('flowfi://app/pair?t=$_token')),
        _token,
      );
    });

    test(
      'reads the QR web URL and router locations, with or without a trailing slash',
      () {
        expect(
          smsPairingTokenFromUri(
            Uri.parse('https://flowfi.web.app/pair/?t=$_token'),
          ),
          _token,
        );
        expect(smsPairingTokenFromUri(Uri.parse('/pair?t=$_token')), _token);
        expect(smsPairingTokenFromUri(Uri.parse('/pair/?t=$_token')), _token);
      },
    );

    test('rejects other paths, other schemes and malformed tokens', () {
      expect(smsPairingTokenFromUri(Uri.parse('/sms-inbox?t=$_token')), isNull);
      expect(
        smsPairingTokenFromUri(Uri.parse('javascript://app/pair?t=$_token')),
        isNull,
      );
      expect(smsPairingTokenFromUri(Uri.parse('flowfi://app/pair')), isNull);
      expect(
        smsPairingTokenFromUri(Uri.parse('flowfi://app/pair?t=short')),
        isNull,
      );
      expect(
        smsPairingTokenFromUri(Uri.parse('flowfi://app/pair?t=${_token}x')),
        isNull,
      );
    });
  });

  group('PendingSmsPairing', () {
    test('holds one valid token until cleared', () {
      final pending = PendingSmsPairing();
      pending.offer('not-a-token');
      expect(pending.hasToken, isFalse);
      pending.offer(_token);
      expect(pending.token, _token);
      pending.clear();
      expect(pending.token, isNull);
    });

    test(
      'drops a token older than maxAge (the web session has expired anyway)',
      () {
        var now = DateTime(2026, 10, 25, 10);
        final pending = PendingSmsPairing(
          clock: () => now,
          maxAge: const Duration(minutes: 15),
        );
        pending.offer(_token);
        now = now.add(const Duration(minutes: 14));
        expect(pending.hasToken, isTrue);
        now = now.add(const Duration(minutes: 2));
        expect(pending.hasToken, isFalse);
      },
    );
  });
}
