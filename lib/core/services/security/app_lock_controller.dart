import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../local_settings_service.dart';
import 'app_lock_state.dart';
import 'pin_hasher.dart';
import 'secure_key_service.dart';

const _pinEnabledKey = 'app_lock_pin_enabled';
const _biometricEnabledKey = 'app_lock_biometric_enabled';
const _autoLockMinutesKey = 'app_lock_auto_minutes';
const _failedAttemptsKey = 'app_lock_failed_attempts';
const _lockoutUntilKey = 'app_lock_lockout_until_epoch_ms';

/// Gatekeeper for the app-lock feature. The router redirects to the lock
/// screen whenever `pinEnabled && locked` — see `core/router/app_router.dart`.
class AppLockController extends Notifier<AppLockState> {
  final _localAuth = LocalAuthentication();

  /// After this many wrong PINs in a row, further attempts are throttled.
  /// A fast offline hash (SHA-256) can otherwise be brute-forced for a
  /// 6-digit PIN in seconds without this — see Milestone 1B security review.
  static const _freeAttempts = 5;
  static const _baseLockout = Duration(seconds: 30);
  static const _maxLockout = Duration(minutes: 5);

  @override
  AppLockState build() {
    final pinEnabled = LocalSettingsService.getBool(_pinEnabledKey);
    final lockoutEpochMs = LocalSettingsService.getIntOrNull(_lockoutUntilKey);

    return AppLockState(
      pinEnabled: pinEnabled,
      biometricEnabled: LocalSettingsService.getBool(_biometricEnabledKey),
      autoLockMinutes: LocalSettingsService.getInt(_autoLockMinutesKey, defaultValue: 1),
      // Lock immediately on cold start whenever a PIN is configured.
      locked: pinEnabled,
      failedAttempts: LocalSettingsService.getInt(_failedAttemptsKey),
      lockoutUntil: lockoutEpochMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lockoutEpochMs),
    );
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    final salt = SecureKeyService.generateSalt();
    final hash = PinHasher.hash(pin, salt);
    await SecureKeyService.savePin(hash, salt);
    await LocalSettingsService.setBool(_pinEnabledKey, true);
    await _resetThrottle();
    state = state.copyWith(pinEnabled: true, locked: false, failedAttempts: 0, clearLockout: true);
  }

  Future<void> disable() async {
    await SecureKeyService.clearPin();
    await LocalSettingsService.setBool(_pinEnabledKey, false);
    await LocalSettingsService.setBool(_biometricEnabledKey, false);
    await _resetThrottle();
    state = state.copyWith(
      pinEnabled: false,
      biometricEnabled: false,
      locked: false,
      failedAttempts: 0,
      clearLockout: true,
    );
  }

  /// Returns false immediately (without touching the stored hash) while a
  /// lockout from prior failed attempts is still active.
  Future<bool> verifyPin(String pin) async {
    if (state.isLockedOut) return false;

    final stored = await SecureKeyService.readPin();
    if (stored == null) return false;

    final valid = PinHasher.verify(pin, stored.salt, stored.hash);
    if (valid) {
      await _resetThrottle();
      state = state.copyWith(locked: false, failedAttempts: 0, clearLockout: true);
      return true;
    }

    final attempts = state.failedAttempts + 1;
    DateTime? lockoutUntil;
    if (attempts >= _freeAttempts) {
      final tier = (attempts - _freeAttempts) ~/ _freeAttempts;
      final lockoutSeconds = (_baseLockout.inSeconds << tier).clamp(0, _maxLockout.inSeconds);
      lockoutUntil = DateTime.now().add(Duration(seconds: lockoutSeconds));
    }

    await LocalSettingsService.setInt(_failedAttemptsKey, attempts);
    if (lockoutUntil == null) {
      await LocalSettingsService.removeKey(_lockoutUntilKey);
    } else {
      await LocalSettingsService.setInt(_lockoutUntilKey, lockoutUntil.millisecondsSinceEpoch);
    }

    state = state.copyWith(failedAttempts: attempts, lockoutUntil: lockoutUntil);
    return false;
  }

  Future<bool> verifyBiometric() async {
    if (state.isLockedOut) return false;
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Unlock to view your finances',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (authenticated) state = state.copyWith(locked: false);
      return authenticated;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await LocalSettingsService.setBool(_biometricEnabledKey, enabled);
    state = state.copyWith(biometricEnabled: enabled);
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    await LocalSettingsService.setInt(_autoLockMinutesKey, minutes);
    state = state.copyWith(autoLockMinutes: minutes);
  }

  /// Called by the app-lifecycle observer when the app has been
  /// backgrounded for longer than [AppLockState.autoLockMinutes].
  void lock() {
    if (state.pinEnabled) state = state.copyWith(locked: true);
  }

  Future<void> _resetThrottle() async {
    await LocalSettingsService.setInt(_failedAttemptsKey, 0);
    await LocalSettingsService.removeKey(_lockoutUntilKey);
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
