import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/onboarding/presentation/providers/onboarding_providers.dart';
import '../../features/setup_wizard/presentation/providers/setup_wizard_providers.dart';
import '../services/security/app_lock_controller.dart';

/// Bridges Riverpod state changes into go_router's `refreshListenable` so
/// the onboarding, auth-gate and lock-screen redirects re-evaluate the
/// moment [OnboardingController]'s flag, [authStateProvider], or
/// [AppLockController]'s `locked` flag flips, without recreating the whole
/// [GoRouter] (which would otherwise wipe every tab's navigation stack).
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    // Fires once, when the tour is finished or skipped — that's what moves
    // the user off `/onboarding` and on to login.
    ref.listen(onboardingCompletedProvider, (previous, next) {
      if (previous != next) notifyListeners();
    });

    // Fires when the wizard is finished or dismissed — that's what moves the
    // user off `/setup` and into the dashboard.
    ref.listen(setupWizardCompletedProvider, (previous, next) {
      if (previous != next) notifyListeners();
    });

    ref.listen(appLockProvider, (previous, next) {
      if (previous?.locked != next.locked) notifyListeners();
    });

    ref.listen(authStateProvider, (previous, next) {
      final previousUid = previous?.value?.uid;
      final nextUid = next.value?.uid;
      if (previous?.isLoading != next.isLoading || previousUid != nextUid) {
        notifyListeners();
      }
    });
  }
}
