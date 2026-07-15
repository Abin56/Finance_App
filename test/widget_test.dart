import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/router/app_router.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/core/theme/theme_controller.dart';
import 'package:finance_app/core/constants/app_strings.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/dashboard/presentation/widgets/dashboard_monthly_summary_cards.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  testWidgets('App boots to the dashboard tab', (WidgetTester tester) async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Balance'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);

    // Scoped to the summary card: these labels also appear elsewhere on the
    // dashboard (e.g. quick actions), so a bare text finder is ambiguous.
    final summaryCards = find.byType(DashboardMonthlySummaryCards);
    expect(summaryCards, findsOneWidget);
    for (final label in ['Income', 'Expense', 'Savings']) {
      expect(find.descendant(of: summaryCards, matching: find.text(label)), findsOneWidget);
    }
  });

  testWidgets('Cash Flow tab shows the moved planning sections', (WidgetTester tester) async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cash Flow'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Cash Flow'), findsOneWidget);
    expect(find.text('Nothing due this month'), findsOneWidget);
  });

  testWidgets('More tab lists secondary destinations and navigates to Reports', (WidgetTester tester) async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'More'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Reports'), findsOneWidget);
  });
}

/// Mirrors `FinanceApp` from `main.dart` minus the lifecycle-driven
/// app-lock observer, which isn't relevant to this smoke test and would
/// otherwise require a real `WidgetsBinding` lifecycle to drive.
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
