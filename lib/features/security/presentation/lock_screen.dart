import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/security/app_lock_controller.dart';
import '../../../shared/widgets/inputs/pin_pad.dart';

/// Full-screen PIN pad shown whenever the app is locked. Pushed by the
/// router redirect in `core/router/app_router.dart` — never navigated to
/// directly, so there's no back button out of it.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  bool _hasError = false;
  bool _isVerifying = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometricUnlock());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometricUnlock() async {
    final controller = ref.read(appLockProvider.notifier);
    if (!ref.read(appLockProvider).biometricEnabled) return;
    if (!await controller.isBiometricAvailable()) return;
    await controller.verifyBiometric();
  }

  Future<void> _onDigit(String digit) async {
    if (_isVerifying || _pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _hasError = false;
    });

    if (_pin.length == 6) {
      setState(() => _isVerifying = true);
      final valid = await ref.read(appLockProvider.notifier).verifyPin(_pin);
      if (!valid && mounted) {
        setState(() {
          _hasError = true;
          _pin = '';
          _isVerifying = false;
        });
      }
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockProvider);
    final isLockedOut = lockState.isLockedOut;
    final remainingSeconds =
        isLockedOut ? lockState.lockoutUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: AppSizes.iconXl, color: context.colors.primary),
              const SizedBox(height: AppSizes.lg),
              Text(AppStrings.appName, style: context.textTheme.headlineSmall),
              const SizedBox(height: AppSizes.sm),
              Text(
                isLockedOut
                    ? 'Too many attempts. Try again in ${remainingSeconds}s'
                    : _hasError
                        ? 'Incorrect PIN, try again'
                        : 'Enter your PIN to unlock',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: (_hasError || isLockedOut)
                      ? context.colors.error
                      : context.colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              PinDotsIndicator(length: 6, filled: _pin.length, hasError: _hasError),
              const SizedBox(height: AppSizes.xxl),
              PinPad(
                enabled: !isLockedOut,
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                leadingIcon: lockState.biometricEnabled ? Icons.fingerprint_rounded : null,
                onLeadingAction: lockState.biometricEnabled ? _tryBiometricUnlock : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
