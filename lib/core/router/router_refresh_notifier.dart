import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../services/security/app_lock_controller.dart';

/// Bridges Riverpod state changes into go_router's `refreshListenable` so
/// the lock-screen and auth-gate redirects re-evaluate the moment
/// [AppLockController]'s `locked` flag or [authStateProvider] flips, without
/// recreating the whole [GoRouter] (which would otherwise wipe every tab's
/// navigation stack).
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
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
