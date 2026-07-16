import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/providers/firebase_providers.dart';
import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/setup_wizard/presentation/providers/setup_wizard_providers.dart';
import 'package:finance_app/features/setup_wizard/presentation/screens/setup_wizard_screen.dart';
import 'package:finance_app/features/sms_inbox/data/sms_permission_service.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_availability.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';

const _widths = <double>[360, 390, 412];
const _shortHeight = 640.0;
const _kUid = 'wizard-uid';
const _pinEnabledKey = 'app_lock_pin_enabled';

/// Keeps the SMS availability provider off the real permission channel and
/// lets a test pick whether the SMS step appears at all.
class _FakeSmsPermissionService implements SmsPermissionService {
  _FakeSmsPermissionService(this._status);

  final SmsAvailability _status;

  @override
  Future<SmsAvailability> checkStatus() async => _status;
  @override
  Future<SmsAvailability> requestPermission() async => _status;
  @override
  Future<void> openSettings() async {}
  @override
  bool get hasRequestedBefore => false;
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // init() caches the prefs instance process-wide, so without the reset a
    // prior test's seeded flags leak into this one. See the onboarding suite.
    LocalSettingsService.resetForTest();
    await LocalSettingsService.init();
    firestore = FakeFirebaseFirestore();
  });

  ProviderContainer container({
    SmsAvailability sms = SmsAvailability.notRequestedYet,
    bool notificationsGranted = false,
  }) {
    final c = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _kUid, email: 't@e.com')),
        ),
        firestoreProvider.overrideWithValue(firestore),
        smsPermissionServiceProvider.overrideWithValue(_FakeSmsPermissionService(sms)),
        notificationsGrantedProvider.overrideWith((ref) async => notificationsGranted),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<ProviderContainer> pumpWizard(
    WidgetTester tester, {
    double width = 390,
    double height = 800,
    SmsAvailability sms = SmsAvailability.notRequestedYet,
    bool notificationsGranted = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = container(sms: sms, notificationsGranted: notificationsGranted);
    // The router only routes to /setup once auth has resolved, so the wizard
    // never reads the user-scoped feature streams before sign-in completes.
    // Reproduce that ordering: let the mock auth stream emit before building,
    // or currentUserIdProvider throws on the first frame.
    await c.read(authStateProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light, home: const SetupWizardScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  /// Asserts a finder is on screen rather than merely built — the same guard
  /// the onboarding suite added after a below-the-fold bug slipped past
  /// findsOneWidget.
  void expectVisible(WidgetTester tester, Finder finder) {
    final screen = tester.getRect(find.byType(SetupWizardScreen));
    final target = tester.getRect(finder);
    expect(
      target.top >= screen.top && target.bottom <= screen.bottom,
      isTrue,
      reason: 'Expected $finder within $screen but it was at $target',
    );
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  group('step flow', () {
    testWidgets('starts on the bank step with a 7-step counter', (tester) async {
      await pumpWizard(tester);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(find.text('Add your bank account'), findsOneWidget);
    });

    testWidgets('Skip walks through every step to completion', (tester) async {
      await pumpWizard(tester);

      const headlines = [
        'Add your bank account',
        'Add a credit card',
        'Add a recurring bill',
        'Scan your bank SMS',
        'Turn on reminders',
        'Protect your data',
      ];
      for (var i = 0; i < headlines.length; i++) {
        expect(find.text(headlines[i]), findsOneWidget, reason: 'on step ${i + 1}');
        await tapText(tester, 'Skip');
      }

      expect(find.text("You're all set!"), findsOneWidget);
      expect(find.text('Step 7 of 7'), findsOneWidget);
      // Nothing left to skip on the final step.
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Skip for now'), findsNothing);
    });

    testWidgets('finishing the last step marks setup complete', (tester) async {
      final c = await pumpWizard(tester);
      for (var i = 0; i < 6; i++) {
        await tapText(tester, 'Skip');
      }

      expect(c.read(setupWizardCompletedProvider), isFalse);
      await tapText(tester, 'Go to Dashboard');
      expect(c.read(setupWizardCompletedProvider), isTrue);
    });

    testWidgets('Skip for now dismisses the whole wizard from the first step', (tester) async {
      final c = await pumpWizard(tester);
      expect(c.read(setupWizardCompletedProvider), isFalse);

      await tapText(tester, 'Skip for now');
      expect(c.read(setupWizardCompletedProvider), isTrue);
    });
  });

  group('adaptive steps', () {
    testWidgets('drops the SMS step where SMS is unsupported', (tester) async {
      await pumpWizard(tester, sms: SmsAvailability.unsupportedPlatform);
      expect(find.text('Step 1 of 6'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        expect(find.text('Scan your bank SMS'), findsNothing);
        await tapText(tester, 'Skip');
      }
      expect(find.text("You're all set!"), findsOneWidget);
    });

    testWidgets('shows a done state and Continue for an already-granted step', (tester) async {
      await pumpWizard(tester, notificationsGranted: true);
      // Skip to the notifications step (bank, card, bill, sms = 4 skips).
      for (var i = 0; i < 4; i++) {
        await tapText(tester, 'Skip');
      }

      expect(find.text('Turn on reminders'), findsOneWidget);
      expect(find.text('Reminders enabled'), findsOneWidget);
      // A satisfied step offers Continue, not the enable action or Skip.
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Enable notifications'), findsNothing);
    });

    testWidgets('reflects a PIN configured earlier as done', (tester) async {
      SharedPreferences.setMockInitialValues({_pinEnabledKey: true});
      LocalSettingsService.resetForTest();
      await LocalSettingsService.init();

      await pumpWizard(tester);
      // Skip to the PIN step (bank, card, bill, sms, notifications = 5 skips).
      for (var i = 0; i < 5; i++) {
        await tapText(tester, 'Skip');
      }

      expect(find.text('Protect your data'), findsOneWidget);
      expect(find.text('Protected with a PIN'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final width in _widths) {
      testWidgets('every step fits at ${width.toInt()}dp', (tester) async {
        await pumpWizard(tester, width: width, height: _shortHeight);

        const headlines = [
          'Add your bank account',
          'Add a credit card',
          'Add a recurring bill',
          'Scan your bank SMS',
          'Turn on reminders',
          'Protect your data',
          "You're all set!",
        ];
        for (var i = 0; i < headlines.length; i++) {
          expectVisible(tester, find.text(headlines[i]));
          if (i < headlines.length - 1) await tapText(tester, 'Skip');
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
