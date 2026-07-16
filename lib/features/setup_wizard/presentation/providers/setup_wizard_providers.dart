import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/local_settings_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Whether the OS notification permission is currently granted, so the
/// wizard's notification step can present itself as already done (e.g. when
/// the user enabled it during onboarding) instead of asking again.
///
/// Invalidate this after requesting the permission to re-read the answer.
final notificationsGrantedProvider = FutureProvider<bool>((ref) async {
  final status = await Permission.notification.status;
  return status.isGranted;
});

/// Storage key for the "this account has seen the setup wizard" flag.
///
/// Scoped per-uid, not per-device like onboarding: the wizard configures
/// account-specific data, so a second account signing in on the same phone
/// deserves its own first run rather than inheriting the first user's.
/// Public so tests driving the real router can seed a returning user.
String setupWizardCompletedKey(String uid) => 'setup_wizard_completed_$uid';

/// Whether the current account has finished (or dismissed) the first-time
/// setup wizard. The router's setup gate reads this — see
/// `core/router/app_router.dart`.
///
/// Rebuilds when the signed-in account changes, so switching users
/// re-evaluates against that user's own flag. Signed out there is nothing to
/// set up, so it reports complete and the gate stays out of the way.
class SetupWizardController extends Notifier<bool> {
  @override
  bool build() {
    final uid = ref.watch(authStateProvider).value?.uid;
    if (uid == null) return true;
    return LocalSettingsService.getBool(setupWizardCompletedKey(uid));
  }

  /// Marks setup done for the current account — whether they completed every
  /// step or dismissed the wizard early. Either way it must not reappear, and
  /// every skipped step stays configurable later from its own section.
  Future<void> complete() async {
    if (state) return;
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    await LocalSettingsService.setBool(setupWizardCompletedKey(uid), true);
    state = true;
  }
}

final setupWizardCompletedProvider =
    NotifierProvider<SetupWizardController, bool>(SetupWizardController.new);
