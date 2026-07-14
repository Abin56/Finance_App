/// Immutable snapshot of the app-lock feature's state.
/// `locked` is in-memory only and resets to `true` (when a PIN is set) on
/// every cold start — persisted preferences are `pinEnabled`,
/// `biometricEnabled`, and `autoLockMinutes`.
///
/// `failedAttempts`/`lockoutUntil` back the brute-force throttle in
/// [AppLockController.verifyPin] and are persisted (not just in-memory) so
/// killing the app can't be used to bypass a lockout.
class AppLockState {
  const AppLockState({
    required this.pinEnabled,
    required this.biometricEnabled,
    required this.autoLockMinutes,
    required this.locked,
    required this.failedAttempts,
    required this.lockoutUntil,
  });

  final bool pinEnabled;
  final bool biometricEnabled;
  final int autoLockMinutes;
  final bool locked;
  final int failedAttempts;
  final DateTime? lockoutUntil;

  bool get isLockedOut => lockoutUntil != null && DateTime.now().isBefore(lockoutUntil!);

  AppLockState copyWith({
    bool? pinEnabled,
    bool? biometricEnabled,
    int? autoLockMinutes,
    bool? locked,
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool clearLockout = false,
  }) {
    return AppLockState(
      pinEnabled: pinEnabled ?? this.pinEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      locked: locked ?? this.locked,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: clearLockout ? null : (lockoutUntil ?? this.lockoutUntil),
    );
  }

  static const initial = AppLockState(
    pinEnabled: false,
    biometricEnabled: false,
    autoLockMinutes: 1,
    locked: false,
    failedAttempts: 0,
    lockoutUntil: null,
  );
}
