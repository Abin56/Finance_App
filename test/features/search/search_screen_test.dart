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
import 'package:finance_app/features/search/presentation/screens/search_screen.dart';

/// Drives global Search through the real router, from its real entry point —
/// `AppRoutes.search` was previously an unregistered constant, so route
/// wiring and discoverability are the things most worth pinning down.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsService.init();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(signedIn: true)),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the dashboard search button opens global Search', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Search anything…'), findsOneWidget);
  });

  testWidgets('Search prompts before a query, and reports no matches after one', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Search everything'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nonexistent');
    // Outlast the 200ms query debounce.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('No matches for "nonexistent"'), findsOneWidget);
  });

  testWidgets('clearing the query returns Search to its prompt state', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nonexistent');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Search everything'), findsNothing);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Search everything'), findsOneWidget);
  });
}

/// Mirrors `FinanceApp` from `main.dart` minus the lifecycle-driven app-lock
/// observer, matching `test/widget_test.dart`'s harness.
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
