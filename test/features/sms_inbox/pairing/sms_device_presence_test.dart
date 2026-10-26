import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/domain/notification_access_availability.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_availability.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_device_presence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'payload has exactly the rules keys and bounded counters, no content',
    () {
      final payload = buildSmsDevicePresencePayload(
        deviceId: 'dev-1',
        label: 'Samsung SM-S918B',
        appVersion: '1.0.1',
        foreground: true,
        smsPermission: 'granted',
        notificationAccess: 'unknown',
        autoSyncEnabled: true,
        sync: SmsPresenceSync(
          phase: SmsPresenceSyncPhase.uploading,
          total: 40,
          done: 12,
          uploaded: 200000,
          updatedAt: DateTime(2026, 10, 25),
        ),
      );
      expect(payload.keys.toSet(), {
        'deviceId',
        'label',
        'platform',
        'appVersion',
        'appState',
        'smsPermission',
        'notificationAccess', //
        'autoSyncEnabled',
        'syncPhase',
        'syncTotal',
        'syncDone',
        'syncUploaded',
        'syncSkipped',
        'syncFailed',
        'syncUpdatedAt', 'lastSyncAt',
      });
      expect(payload['appState'], 'foreground');
      expect(payload['syncPhase'], 'uploading');
      expect(payload['syncUploaded'], 100000);
      expect(payload['syncUpdatedAt'], isA<Timestamp>());
    },
  );

  test('sync state round-trips through the shared cache', () {
    final s = SmsPresenceSync(
      phase: SmsPresenceSyncPhase.done,
      total: 3,
      done: 3,
      uploaded: 2,
      skipped: 1,
      lastSyncAt: DateTime(2026, 10, 25, 9),
    );
    final back = SmsPresenceSync.fromJson(s.toJson());
    expect(back.phase, SmsPresenceSyncPhase.done);
    expect(back.total, 3);
    expect(back.skipped, 1);
    expect(back.lastSyncAt, DateTime(2026, 10, 25, 9));
    expect(SmsPresenceSync.fromJson('junk').phase, SmsPresenceSyncPhase.idle);
  });

  test('report caches values but writes nothing when signed out', () async {
    SharedPreferences.setMockInitialValues({});
    final reporter = SmsDevicePresenceReporter(
      currentUid: () => null,
      installId: () async => 'dev-1',
    );
    final wrote = await reporter.report(
      foreground: true,
      permission: SmsAvailability.granted,
      notificationAccess: NotificationAccessAvailability.granted,
      autoSyncEnabled: true,
      sync: const SmsPresenceSync(phase: SmsPresenceSyncPhase.scanning),
    );
    expect(wrote, isFalse);
    expect(
      (await SmsDevicePresenceReporter.readSync()).phase,
      SmsPresenceSyncPhase.scanning,
    );
  });

  test(
    'progress throttle: phase changes always sent, per-item updates throttled, writes serialized',
    () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 10, 25, 10);
      final sent = <SmsPresenceSyncPhase>[];
      final reporter = _RecordingReporter(sent);
      final t = SmsPresenceProgressThrottle(reporter, clock: () => now);
      await t.update(
        const SmsPresenceSync(phase: SmsPresenceSyncPhase.scanning),
      );
      await t.update(
        const SmsPresenceSync(
          phase: SmsPresenceSyncPhase.uploading,
          total: 10,
          done: 0,
        ),
      );
      await t.update(
        const SmsPresenceSync(
          phase: SmsPresenceSyncPhase.uploading,
          total: 10,
          done: 1,
        ),
      ); // throttled
      now = now.add(const Duration(seconds: 2));
      await t.update(
        const SmsPresenceSync(
          phase: SmsPresenceSyncPhase.uploading,
          total: 10,
          done: 5,
        ),
      );
      await t.flush();
      expect(sent, [
        SmsPresenceSyncPhase.scanning,
        SmsPresenceSyncPhase.uploading,
        SmsPresenceSyncPhase.uploading,
      ]);
      expect(t.last.done, 5);
    },
  );
}

class _RecordingReporter extends SmsDevicePresenceReporter {
  _RecordingReporter(this.sent) : super(currentUid: () => null);
  final List<SmsPresenceSyncPhase> sent;

  @override
  Future<bool> report({
    bool? foreground,
    SmsAvailability? permission,
    NotificationAccessAvailability? notificationAccess,
    bool? autoSyncEnabled,
    String? label,
    SmsPresenceSync? sync,
    bool force = false,
  }) async {
    if (sync != null) sent.add(sync.phase);
    return true;
  }
}
