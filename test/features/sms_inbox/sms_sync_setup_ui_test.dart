import 'package:finance_app/features/sms_inbox/data/sms_auto_sync_service.dart';
import 'package:finance_app/features/sms_inbox/domain/notification_access_availability.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_auto_sync_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_sync_diagnostics.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_device_presence.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_auto_sync_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_auto_sync_card.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_pairing_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService extends SmsAutoSyncService {
  _FakeService({required this.granted, required this.enabled});

  final bool granted;
  final bool enabled;
  int scans = 0;

  @override
  Future<SmsAutoSyncStatus> getStatus() async => SmsAutoSyncStatus(
    supported: true,
    enabled: enabled,
    receiveSmsGranted: granted,
    readSmsGranted: granted,
    pendingSignals: 0,
    rejectedCount: 0,
    retryCount: 0,
  );

  @override
  Future<void> scanNow() async => scans++;
}

class _FakeItems extends SmsInboxItemsNotifier {
  @override
  Future<List<SmsInboxItem>> build() async => const [];
}

class _FakeNotificationAccess extends NotificationAccessAvailabilityNotifier {
  @override
  Future<NotificationAccessAvailability> build() async =>
      NotificationAccessAvailability.denied;
}

Future<_FakeService> _pump(
  WidgetTester tester, {
  required bool granted,
  required bool enabled,
  Widget child = const SmsAutoSyncCard(),
  bool disableAnimations = false,
  ThemeData? theme,
}) async {
  SharedPreferences.setMockInitialValues({});
  final service = _FakeService(granted: granted, enabled: enabled);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        smsAutoSyncServiceProvider.overrideWithValue(service),
        smsSyncDiagnosticsProvider.overrideWith(
          (ref) async => const SmsSyncDiagnostics(),
        ),
        smsLiveSyncProvider.overrideWith(
          (ref) => Stream.value(const SmsPresenceSync()),
        ),
        smsInboxItemsProvider.overrideWith(_FakeItems.new),
        notificationAccessAvailabilityProvider.overrideWith(
          _FakeNotificationAccess.new,
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return service;
}

/// The step whose title is [title], announced as "Step n of 4, state".
Finder _step(int index, String title, String state) => find.ancestor(
  of: find.text(title),
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Step $index of 4, $state',
  ),
);

void main() {
  group('SmsAutoSyncCard — tracker reflects real state only', () {
    testWidgets('nothing granted: SMS access is next, the rest wait', (
      tester,
    ) async {
      await _pump(tester, granted: false, enabled: false);
      expect(find.text('0 of 3'), findsOneWidget);
      expect(_step(1, 'SMS access', 'next'), findsOneWidget);
      expect(_step(2, 'Notification access', 'optional'), findsOneWidget);
      expect(_step(3, 'Auto Sync', 'not started'), findsOneWidget);
      expect(_step(4, 'Pair with FlowFi Web', 'not started'), findsOneWidget);
      expect(find.text('Needed to read bank alerts'), findsOneWidget);
      expect(find.text('After Auto Sync is on'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Allow'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);
      // No Scan now until Auto Sync is actually effective.
      expect(find.text('Scan now'), findsNothing);
    });

    testWidgets('SMS + Auto Sync on, unpaired: pairing is next', (
      tester,
    ) async {
      await _pump(tester, granted: true, enabled: true);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(_step(1, 'SMS access', 'done'), findsOneWidget);
      expect(_step(3, 'Auto Sync', 'done'), findsOneWidget);
      expect(_step(4, 'Pair with FlowFi Web', 'next'), findsOneWidget);
      expect(
        find.text("Scan the QR using your phone's Camera."),
        findsOneWidget,
      );
      // Done steps drop their supporting text.
      expect(find.text('Needed to read bank alerts'), findsNothing);
      // Unpaired: never collapses into the "Ready" summary.
      expect(find.text('Ready'), findsNothing);
      expect(find.text('Manage'), findsNothing);
    });

    testWidgets('Scan now is still wired to the Auto Sync service', (
      tester,
    ) async {
      final service = await _pump(tester, granted: true, enabled: true);
      await tester.tap(find.text('Scan now'));
      await tester.pump();
      expect(service.scans, 1);
    });

    testWidgets('notification Turn on still opens the access dialog', (
      tester,
    ) async {
      await _pump(tester, granted: true, enabled: true);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Turn on'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('settles (no endless animation) and fits a 320dp phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, granted: false, enabled: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme renders without errors', (tester) async {
      await _pump(
        tester,
        granted: true,
        enabled: true,
        theme: ThemeData.dark(),
      );
      expect(tester.takeException(), isNull);
      expect(_step(4, 'Pair with FlowFi Web', 'next'), findsOneWidget);
    });
  });

  group('SmsPairFirstEmptyState', () {
    testWidgets('points at the next real step instead of repeating it', (
      tester,
    ) async {
      await _pump(
        tester,
        granted: false,
        enabled: false,
        child: const SmsPairFirstEmptyState(),
      );
      expect(
        find.text('Pair with FlowFi Web to see your bank SMS here'),
        findsOneWidget,
      );
      expect(find.text('Next: allow SMS access above'), findsOneWidget);
      expect(find.textContaining('leave FlowFi for a moment'), findsOneWidget);
    });

    testWidgets('once Auto Sync is on, sends the user to FlowFi Web', (
      tester,
    ) async {
      await _pump(
        tester,
        granted: true,
        enabled: true,
        child: const SmsPairFirstEmptyState(),
      );
      expect(find.textContaining("You're ready"), findsOneWidget);
    });

    testWidgets('guide walks Web QR → Camera → link → Approve and loops', (
      tester,
    ) async {
      await _pump(
        tester,
        granted: true,
        enabled: true,
        child: const SmsPairingGuide(),
      );
      expect(find.text('1 of 4'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2600));
      expect(find.text('2 of 4'), findsOneWidget);
      // Tapping a segment jumps there.
      await tester.tap(find.byType(InkWell).at(3));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('4 of 4'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2700));
      expect(find.text('1 of 4'), findsOneWidget);
      // The guide is a demonstration — it never claims a paired result.
      expect(find.textContaining('Paired'), findsNothing);
    });

    testWidgets('reduced motion: static scene and every step listed', (
      tester,
    ) async {
      await _pump(
        tester,
        granted: true,
        enabled: true,
        disableAnimations: true,
        child: const SmsPairingGuide(),
      );
      await tester.pumpAndSettle();
      for (final beat in smsPairingGuideBeats) {
        expect(find.text(beat.body), findsOneWidget);
      }
      expect(find.text('1 of 4'), findsNothing);
    });

    testWidgets('large text scaling does not overflow at 320dp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            smsAutoSyncServiceProvider.overrideWithValue(
              _FakeService(granted: true, enabled: true),
            ),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(1.6),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: SingleChildScrollView(child: SmsPairFirstEmptyState()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
