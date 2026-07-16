import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finance_app/core/services/local_settings_service.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:finance_app/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:finance_app/features/sms_inbox/data/sms_permission_service.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_availability.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/shared/widgets/buttons/primary_button.dart';

/// The three Android widths the tour has to survive, paired with a short
/// viewport — a tall screen hides exactly the overflow this is looking for.
const _widths = <double>[360, 390, 412];
const _shortHeight = 640.0;

/// Stands in for the real permission service so tests never reach
/// `permission_handler`'s platform channel, and so both branches of the SMS
/// page (can ask / nothing to ask) are reachable on any host.
class _FakeSmsPermissionService implements SmsPermissionService {
  _FakeSmsPermissionService(this._status);

  SmsAvailability _status;
  int requestCount = 0;

  @override
  Future<SmsAvailability> checkStatus() async => _status;

  @override
  Future<SmsAvailability> requestPermission() async {
    requestCount++;
    return _status = SmsAvailability.granted;
  }

  @override
  Future<void> openSettings() async {}

  @override
  bool get hasRequestedBefore => requestCount > 0;
}

void main() {
  late _FakeSmsPermissionService smsService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Order matters: setMockInitialValues hands out a fresh instance, so
    // without the reset LocalSettingsService keeps answering from the
    // previous test's instance and every test after the first would start
    // with the tour already completed.
    LocalSettingsService.resetForTest();
    await LocalSettingsService.init();
    smsService = _FakeSmsPermissionService(SmsAvailability.notRequestedYet);
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [smsPermissionServiceProvider.overrideWithValue(smsService)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> pumpTour(
    WidgetTester tester, {
    double width = 390,
    double height = 800,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = buildContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Taps a keyed button and lets the page-slide plus entry animations finish.
  Future<void> tapAndSettle(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key).first);
    await tester.pumpAndSettle();
  }

  Future<void> tapPrimary(WidgetTester tester) =>
      tapAndSettle(tester, OnboardingScreen.primaryActionKey);

  Future<void> tapSecondary(WidgetTester tester) =>
      tapAndSettle(tester, OnboardingScreen.secondaryActionKey);

  String primaryLabel(WidgetTester tester) =>
      tester.widget<PrimaryButton>(find.byKey(OnboardingScreen.primaryActionKey)).label;

  /// Walks from the welcome page to the final page, declining every optional
  /// step — the path a cautious user takes, and the one that reaches the end
  /// without touching a permission plugin.
  Future<void> walkToLastPage(WidgetTester tester) async {
    await tapPrimary(tester); // Get Started
    await tapSecondary(tester); // Skip for Now (SMS)
    await tapPrimary(tester); // Continue (payment tracking)
    await tapSecondary(tester); // Skip (notifications)
    await tapSecondary(tester); // Skip (security)
  }

  /// Asserts [finder] is actually on screen, not merely built.
  ///
  /// `findsOneWidget` is not enough here and previously hid a real bug: the
  /// SMS page's privacy note sat below the fold inside a scroll view, built
  /// and found by every finder but never seen by a user.
  void expectVisibleInPage(WidgetTester tester, Finder finder) {
    final page = tester.getRect(find.byType(PageView));
    final target = tester.getRect(finder);
    expect(
      target.bottom <= page.bottom && target.top >= page.top,
      isTrue,
      reason: 'Expected $finder on screen, but it sits at $target outside the page viewport $page',
    );
  }

  group('layout', () {
    for (final width in _widths) {
      testWidgets('every page lays out at ${width.toInt()}dp without overflow', (tester) async {
        await pumpTour(tester, width: width, height: _shortHeight);

        // Walking the whole tour is itself the assertion: a RenderFlex
        // overflow on any page surfaces as a pumped exception.
        expectVisibleInPage(tester, find.text('Manage all your money in one place.'));

        await tapPrimary(tester);
        expect(find.text('Smart SMS detection'), findsOneWidget);
        // The privacy promise is the whole reason this page persuades anyone
        // to grant SMS access — it has to be on screen next to the button
        // that asks, not reachable by scrolling.
        expectVisibleInPage(
          tester,
          find.text('Your SMS stays on your device until you choose to convert it.'),
        );

        await tapSecondary(tester);
        expectVisibleInPage(tester, find.text('Every payment, tracked'));

        await tapPrimary(tester);
        expectVisibleInPage(tester, find.text('Never miss an important payment.'));

        await tapSecondary(tester);
        expectVisibleInPage(tester, find.text('Protect your financial data.'));

        await tapSecondary(tester);
        expectVisibleInPage(tester, find.text('You\'re all set!'));

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('progress and skipping', () {
    testWidgets('shows one progress dot per page', (tester) async {
      await pumpTour(tester);
      expect(find.bySemanticsLabel('Step 1 of 6'), findsOneWidget);

      await tapPrimary(tester);
      expect(find.bySemanticsLabel('Step 2 of 6'), findsOneWidget);
    });

    testWidgets('top-bar Skip ends the tour from a middle page', (tester) async {
      final container = await pumpTour(tester);
      expect(container.read(onboardingCompletedProvider), isFalse);

      await tapPrimary(tester);
      await tapSecondary(tester);
      await tapAndSettle(tester, OnboardingScreen.skipTourKey);

      expect(container.read(onboardingCompletedProvider), isTrue);
    });

    testWidgets('top-bar Skip is disabled on the final page', (tester) async {
      await pumpTour(tester);
      await walkToLastPage(tester);

      final skip = tester.widget<TextButton>(find.byKey(OnboardingScreen.skipTourKey));
      expect(skip.onPressed, isNull);
    });

    testWidgets('finishing the last page ends the tour', (tester) async {
      final container = await pumpTour(tester);
      await walkToLastPage(tester);

      expect(primaryLabel(tester), 'Start Using FlowFi');
      expect(container.read(onboardingCompletedProvider), isFalse);

      await tapPrimary(tester);
      expect(container.read(onboardingCompletedProvider), isTrue);
    });

    testWidgets('the tour never reappears once it has been seen', (tester) async {
      final container = await pumpTour(tester);
      await container.read(onboardingCompletedProvider.notifier).complete();

      // A fresh container reads the same persisted flag a cold start would.
      expect(buildContainer().read(onboardingCompletedProvider), isTrue);
    });
  });

  group('SMS page', () {
    testWidgets('requesting SMS access asks once, then moves on', (tester) async {
      await pumpTour(tester);
      await tapPrimary(tester);
      expect(primaryLabel(tester), 'Enable SMS Detection');

      await tapPrimary(tester);

      expect(smsService.requestCount, 1);
      expect(find.text('Every payment, tracked'), findsOneWidget);
    });

    testWidgets('declining SMS access moves on without asking', (tester) async {
      await pumpTour(tester);
      await tapPrimary(tester);

      await tapSecondary(tester);

      expect(smsService.requestCount, 0);
      expect(find.text('Every payment, tracked'), findsOneWidget);
    });

    testWidgets('offers no ask on a platform that cannot read SMS', (tester) async {
      smsService = _FakeSmsPermissionService(SmsAvailability.unsupportedPlatform);
      await pumpTour(tester);
      await tapPrimary(tester);

      expect(primaryLabel(tester), 'Continue');
      expect(find.byKey(OnboardingScreen.secondaryActionKey), findsNothing);
    });

    testWidgets('offers no ask when access was already granted', (tester) async {
      smsService = _FakeSmsPermissionService(SmsAvailability.granted);
      await pumpTour(tester);
      await tapPrimary(tester);

      expect(primaryLabel(tester), 'Continue');
      expect(find.byKey(OnboardingScreen.secondaryActionKey), findsNothing);
    });
  });
}
