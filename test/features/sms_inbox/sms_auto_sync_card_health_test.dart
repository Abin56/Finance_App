import 'package:finance_app/features/sms_inbox/data/sms_auto_sync_service.dart';
import 'package:finance_app/features/sms_inbox/domain/notification_access_availability.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_auto_sync_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_inbox_item.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_sync_diagnostics.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_device_presence.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_auto_sync_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/providers/sms_inbox_providers.dart';
import 'package:finance_app/features/sms_inbox/presentation/widgets/sms_auto_sync_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStatusService extends SmsAutoSyncService {
  const _FakeStatusService();

  @override
  Future<SmsAutoSyncStatus> getStatus() async => const SmsAutoSyncStatus(
    supported: true,
    enabled: true,
    receiveSmsGranted: true,
    readSmsGranted: true,
    pendingSignals: 0,
    rejectedCount: 0,
    retryCount: 0,
  );
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

Future<void> _pump(WidgetTester tester, SmsSyncDiagnostics diag) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        smsAutoSyncServiceProvider.overrideWithValue(
          const _FakeStatusService(),
        ),
        smsSyncDiagnosticsProvider.overrideWith((ref) async => diag),
        smsLiveSyncProvider.overrideWith(
          (ref) => Stream.value(const SmsPresenceSync()),
        ),
        smsInboxItemsProvider.overrideWith(_FakeItems.new),
        notificationAccessAvailabilityProvider.overrideWith(
          _FakeNotificationAccess.new,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SmsAutoSyncCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The support diagnostics live in the Details sheet.
  await tester.tap(find.text('Details'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows scan attempt/success and Cloud Sync Off by default', (
    tester,
  ) async {
    await _pump(
      tester,
      SmsSyncDiagnostics(
        lastAttemptAt: DateTime(2026, 10, 25, 9),
        lastScanSuccessAt: DateTime(2026, 10, 25, 9),
        cloudState: SmsCloudSyncState.disabled,
      ),
    );
    expect(find.text('Last scan attempt'), findsOneWidget);
    expect(find.text('Last successful scan'), findsOneWidget);
    expect(find.text('Cloud Sync'), findsOneWidget);
    expect(find.text('Off'), findsWidgets);
    expect(find.text('Last cloud upload'), findsNothing);
    expect(find.textContaining('stay on this device'), findsOneWidget);
  });

  testWidgets('unverified Cloud Sync is shown as such, with a safe reason', (
    tester,
  ) async {
    await _pump(
      tester,
      const SmsSyncDiagnostics(
        cloudState: SmsCloudSyncState.unverified,
        cloudUnverifiedReason: SmsSyncFailureCategory.offline,
      ),
    );
    expect(find.text("Can't verify"), findsOneWidget);
    expect(find.textContaining('no connection'), findsOneWidget);
    expect(find.textContaining('nothing is uploaded'), findsOneWidget);
  });

  testWidgets('enabled Cloud Sync shows the upload row and a failure note', (
    tester,
  ) async {
    await _pump(
      tester,
      SmsSyncDiagnostics(
        cloudState: SmsCloudSyncState.enabled,
        lastUploadFailure: SmsSyncFailureCategory.permissionDenied,
        consecutiveUploadFailures: 1,
      ),
    );
    expect(find.text('On'), findsWidgets);
    expect(find.text('Last cloud upload'), findsOneWidget);
    expect(find.textContaining('the server denied permission'), findsOneWidget);
  });
}
