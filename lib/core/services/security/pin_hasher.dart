import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Salts and hashes the app-lock PIN with SHA-256 so the raw PIN is never
/// stored or compared directly, even within secure storage.
abstract class PinHasher {
  PinHasher._();

  static String hash(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static bool verify(String pin, String salt, String expectedHash) {
    return hash(pin, salt) == expectedHash;
  }
}
