import 'package:finance_app/core/services/security/app_lock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLockState.isLockedOut', () {
    test('is false when lockoutUntil is null', () {
      const state = AppLockState.initial;
      expect(state.isLockedOut, isFalse);
    });

    test('is true when lockoutUntil is in the future', () {
      final state = AppLockState.initial.copyWith(
        lockoutUntil: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(state.isLockedOut, isTrue);
    });

    test('is false when lockoutUntil is in the past', () {
      final state = AppLockState.initial.copyWith(
        lockoutUntil: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(state.isLockedOut, isFalse);
    });
  });

  group('AppLockState.copyWith', () {
    test('preserves unspecified fields', () {
      const state = AppLockState(
        pinEnabled: true,
        biometricEnabled: true,
        autoLockMinutes: 5,
        locked: true,
        failedAttempts: 2,
        lockoutUntil: null,
      );

      final copy = state.copyWith(failedAttempts: 3);

      expect(copy.pinEnabled, isTrue);
      expect(copy.biometricEnabled, isTrue);
      expect(copy.autoLockMinutes, 5);
      expect(copy.locked, isTrue);
      expect(copy.failedAttempts, 3);
    });

    test('clearLockout: true clears lockoutUntil even if a new value is also passed', () {
      final state = AppLockState.initial.copyWith(
        lockoutUntil: DateTime.now().add(const Duration(minutes: 1)),
      );

      final copy = state.copyWith(
        lockoutUntil: DateTime.now().add(const Duration(minutes: 5)),
        clearLockout: true,
      );

      expect(copy.lockoutUntil, isNull);
    });

    test('without clearLockout, an explicit lockoutUntil overrides the previous value', () {
      final firstLockout = DateTime.now().add(const Duration(minutes: 1));
      final secondLockout = DateTime.now().add(const Duration(minutes: 5));
      final state = AppLockState.initial.copyWith(lockoutUntil: firstLockout);

      final copy = state.copyWith(lockoutUntil: secondLockout);

      expect(copy.lockoutUntil, secondLockout);
    });
  });
}
