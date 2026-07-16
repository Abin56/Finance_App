import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/constants/app_strings.dart';
import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/router/app_router.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/core/theme/theme_controller.dart';
import 'package:finance_app/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:finance_app/features/setup_wizard/presentation/providers/setup_wizard_providers.dart';
import 'package:finance_app/features/setup_wizard/presentation/screens/setup_wizard_screen.dart';
import 'package:finance_app/features/sms_inbox/data/sms_permission_service.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_availability.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';

const _kUid = 'gate-uid';

/// Off the real SMS permission channel; unsupported keeps the SMS step out so
/// the wizard's shape is deterministic here.
class _NoSms extends SmsPermissionService {
  const _NoSms();
  @override
  Future<SmsAvailability> checkStatus() async => SmsAvailability.unsupportedPlatform;
}

/// Drives the real router, the way the app actually reaches the wizard: a
/// signed-in account that has finished onboarding but not the setup wizard.
void main() {
  Widget app() {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _kUid, email: 't@e.com')),
        ),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        smsPermissionServiceProvider.overrideWithValue(const _NoSms()),
        notificationsGrantedProvider.overrideWith((ref) async => false),
      ],
      child: const _TestApp(),
    );
  }

  testWidgets('a first-time account lands on the setup wizard after login', (tester) async {
    SharedPreferences.setMockInitialValues({onboardingCompletedKey: true});
    LocalSettingsService.resetForTest();
    await LocalSettingsService.init();

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(SetupWizardScreen), findsOneWidget);
    expect(find.text('Add your bank account'), findsOneWidget);
  });

  testWidgets('Skip for now dismisses the wizard through to the dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({onboardingCompletedKey: true});
    LocalSettingsService.resetForTest();
    await LocalSettingsService.init();

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupWizardScreen), findsNothing);
    expect(find.text('Total Balance'), findsOneWidget);
  });

  testWidgets('an account that already finished setup boots straight to the dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({
      onboardingCompletedKey: true,
      setupWizardCompletedKey(_kUid): true,
    });
    LocalSettingsService.resetForTest();
    await LocalSettingsService.init();

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(SetupWizardScreen), findsNothing);
    expect(find.text('Total Balance'), findsOneWidget);
  });
}

/// Mirrors `FinanceApp` minus the lifecycle app-lock observer, as in
/// widget_test.dart.
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
