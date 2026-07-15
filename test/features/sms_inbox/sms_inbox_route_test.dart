import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/router/app_router.dart';
import 'package:finance_app/core/router/app_routes.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/sms_inbox/data/sms_permission_service.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_availability.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';

/// Keeps the screen off the real `permission_handler` platform channel and on
/// its permission gate, which is enough to assert what the shell paints.
class _GatedPermissionService extends SmsPermissionService {
  const _GatedPermissionService();

  @override
  Future<SmsAvailability> checkStatus() async => SmsAvailability.notRequestedYet;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  Widget app() {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        smsPermissionServiceProvider.overrideWithValue(const _GatedPermissionService()),
      ],
      child: const _TestApp(),
    );
  }

  // Runs at the default surface size rather than across 360/390/412: whether
  // the FAB is in the tree at all is width-independent, and narrowing the
  // surface makes the dashboard *behind* this route trip a RenderFlex
  // overflow under flutter_test's fixed-width fallback font — an artifact of
  // the test font, not a real layout bug. The width matrix that matters lives
  // in test/core/router/fab_visibility_test.dart.
  testWidgets('SMS Inbox opens clear of the shell FAB and nav bar', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Baseline: the shell chrome is up on a tab, so the assertions below
    // prove the route change and not just a broken finder.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    GoRouter.of(tester.element(find.byType(NavigationBar))).push(AppRoutes.smsInbox);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'SMS Inbox'), findsOneWidget);
    expect(
      find.byIcon(Icons.add_rounded),
      findsNothing,
      reason: 'the shell FAB must not float over SMS Inbox or its sheets',
    );
    expect(find.byType(NavigationBar), findsNothing, reason: 'SMS Inbox is a full-screen drill-in');

    // Its own back button still works, i.e. the drill-in is escapable.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_rounded), findsOneWidget, reason: 'shell chrome returns on pop');
  });
}

/// Mirrors `FinanceApp` from `main.dart` minus the lifecycle-driven app-lock
/// observer, matching the harness in `test/widget_test.dart`.
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
