import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/local_settings_service.dart';

/// Storage key for the "tour has been seen" flag.
///
/// Public, unlike the other controllers' private keys, so tests driving the
/// real router can seed a returning user — without it the onboarding gate
/// sends every route to the tour and no test can reach the app.
const onboardingCompletedKey = 'onboarding_completed';

/// Whether the intro tour has been finished *or* skipped — either way the
/// user has seen it, and it must never appear again. Stored per-device
/// rather than per-account: onboarding runs before sign-in, so there is no
/// account to hang it off yet.
///
/// The router's first gate reads this — see `core/router/app_router.dart`.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() => LocalSettingsService.getBool(onboardingCompletedKey);

  /// Marks the tour as seen, which flips the router's onboarding gate and
  /// hands the user on to the auth gate.
  Future<void> complete() async {
    if (state) return;
    await LocalSettingsService.setBool(onboardingCompletedKey, true);
    state = true;
  }
}

final onboardingCompletedProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
