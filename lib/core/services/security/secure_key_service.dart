import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns the salted PIN hash for app-lock. Backed by the platform
/// keystore/keychain via [FlutterSecureStorage] — never stored in plain
/// local prefs, since that would defeat the point.
///
/// SECURITY NOTE: this only covers the app-lock PIN. Under Hive (pre-Firebase
/// migration), every local box was opened with `HiveAesCipher`, so the whole
/// database was encrypted at rest. Firestore's offline persistence cache is
/// a local SQLite database that Firestore does not support encrypting at the
/// SDK level, so financial data in that cache is currently plaintext on
/// disk. If at-rest encryption of synced data is a hard requirement, it
/// needs app-level field encryption before `toFirestore()` (and decryption
/// in `fromFirestore()`), which is a real feature to design, not a quick fix.
class SecureKeyService {
  SecureKeyService._();

  static const _storage = FlutterSecureStorage();

  static const _pinSaltStorageKey = 'app_pin_salt';
  static const _pinHashStorageKey = 'app_pin_hash';

  static Future<void> savePin(String hash, String salt) async {
    await _storage.write(key: _pinHashStorageKey, value: hash);
    await _storage.write(key: _pinSaltStorageKey, value: salt);
  }

  static Future<({String hash, String salt})?> readPin() async {
    final hash = await _storage.read(key: _pinHashStorageKey);
    final salt = await _storage.read(key: _pinSaltStorageKey);
    if (hash == null || salt == null) return null;
    return (hash: hash, salt: salt);
  }

  static Future<void> clearPin() async {
    await _storage.delete(key: _pinHashStorageKey);
    await _storage.delete(key: _pinSaltStorageKey);
  }

  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }
}
