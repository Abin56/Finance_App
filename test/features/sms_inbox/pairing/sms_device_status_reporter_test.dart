import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_availability.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_sync_diagnostics.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_device_status_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'uid-owner';
const _device = '0b5a3f4e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';

/// The exact key set firestore.rules requires (plus `reportedAt`, set by the writer).
const _ruleKeys = {
  'deviceId',
  'smsPermission',
  'autoSyncEnabled',
  'cloudSync',
  'lastScanAt',
  'lastScanOutcome',
  'lastUploadAt',
  'lastUploadOutcome',
  'lastUploadedCount',
  'pendingNotOwnedCount',
  'appVersion',
};

class _DenyingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildSmsDeviceStatusPayload', () {
    test(
      'carries exactly the rules schema — counters, codes and timestamps only',
      () {
        final payload = buildSmsDeviceStatusPayload(
          deviceId: _device,
          smsPermission: 'granted',
          autoSyncEnabled: true,
          diagnostics: SmsSyncDiagnostics(
            lastAttemptAt: DateTime(2026, 10, 25, 10, 1),
            lastScanSuccessAt: DateTime(2026, 10, 25, 10, 1),
            cloudState: SmsCloudSyncState.enabled,
            lastUploadSuccessAt: DateTime(2026, 10, 25, 10, 2),
            lastUploadSkippedNotOwned: 7,
          ),
          lastUploadedCount: 3,
          appVersion: '1.0.0+1',
        );
        expect(payload.keys.toSet(), _ruleKeys);
        expect(payload['cloudSync'], 'enabled');
        expect(payload['lastScanOutcome'], 'ok');
        expect(payload['lastUploadOutcome'], 'ok');
        expect(payload['pendingNotOwnedCount'], 7);
        expect(payload['lastScanAt'], isA<Timestamp>());
      },
    );

    test('a failed latest scan reports the attempt time and why', () {
      final denied = buildSmsDeviceStatusPayload(
        deviceId: _device,
        smsPermission: 'denied',
        autoSyncEnabled: true,
        diagnostics: SmsSyncDiagnostics(
          lastAttemptAt: DateTime(2026, 10, 25, 11),
          lastScanSuccessAt: DateTime(2026, 10, 24),
          lastScanError: 'permission',
        ),
        lastUploadedCount: 0,
      );
      expect(denied['lastScanOutcome'], 'permission');
      expect(
        (denied['lastScanAt'] as Timestamp).toDate(),
        DateTime(2026, 10, 25, 11),
      );

      final failed = buildSmsDeviceStatusPayload(
        deviceId: _device,
        smsPermission: 'granted',
        autoSyncEnabled: true,
        diagnostics: SmsSyncDiagnostics(
          lastAttemptAt: DateTime(2026, 10, 25, 11),
          lastScanError: 'scan_failed',
        ),
        lastUploadedCount: 0,
      );
      expect(failed['lastScanOutcome'], 'failed');
    });

    test(
      'the more recent of upload success/failure wins; nothing reported before any scan',
      () {
        final payload = buildSmsDeviceStatusPayload(
          deviceId: _device,
          smsPermission: 'unknown',
          autoSyncEnabled: false,
          diagnostics: SmsSyncDiagnostics(
            lastUploadSuccessAt: DateTime(2026, 10, 25, 9),
            lastUploadFailureAt: DateTime(2026, 10, 25, 10),
            lastUploadFailure: SmsSyncFailureCategory.offline,
          ),
          lastUploadedCount: 0,
        );
        expect(payload['lastUploadOutcome'], 'failed');
        expect(payload['lastScanAt'], isNull);
        expect(payload['lastScanOutcome'], isNull);
        expect(payload['cloudSync'], isNull);
      },
    );
  });

  group('SmsDeviceStatusReporter', () {
    late FakeFirebaseFirestore firestore;
    late List<String?> savedUids;
    String? pairedUid;
    var now = DateTime(2026, 10, 25, 10);

    SmsDeviceStatusReporter reporter({FakeFirebaseFirestore? db}) =>
        SmsDeviceStatusReporter(
          firestore: () => db ?? firestore,
          currentUid: () => _uid,
          installId: () async => _device,
          pairedUid: () async => pairedUid,
          savePairedUid: (uid) async {
            savedUids.add(uid);
            pairedUid = uid;
          },
          diagnostics: () async => SmsSyncDiagnostics(
            lastScanSuccessAt: DateTime(2026, 10, 25, 9),
            cloudState: SmsCloudSyncState.enabled,
          ),
          clock: () => now,
        );

    DocumentReference<Map<String, dynamic>> statusDoc() => firestore
        .collection('users')
        .doc(_uid)
        .collection('smsDeviceStatus')
        .doc(_device);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      savedUids = [];
      pairedUid = _uid;
      now = DateTime(2026, 10, 25, 10);
    });

    test(
      'an install not paired to the signed-in account never writes',
      () async {
        pairedUid = 'someone-else';
        expect(
          await reporter().report(permission: SmsAvailability.granted),
          isFalse,
        );
        expect((await statusDoc().get()).exists, isFalse);
        pairedUid = null;
        expect(
          await reporter().report(permission: SmsAvailability.granted),
          isFalse,
        );
      },
    );

    test(
      'a paired phone writes its status with a server timestamp, merging what each side knows',
      () async {
        expect(
          await reporter().report(permission: SmsAvailability.granted),
          isTrue,
        );
        var data = (await statusDoc().get()).data()!;
        expect(data['smsPermission'], 'granted');
        expect(data['autoSyncEnabled'], isFalse);
        expect(data.containsKey('reportedAt'), isTrue);

        // The background worker knows Auto Sync is on and its upload count; the cached permission is kept.
        now = now.add(const Duration(minutes: 5));
        expect(
          await reporter().report(autoSyncEnabled: true, uploadedCount: 4),
          isTrue,
        );
        data = (await statusDoc().get()).data()!;
        expect(data['smsPermission'], 'granted');
        expect(data['autoSyncEnabled'], isTrue);
        expect(data['lastUploadedCount'], 4);
        expect(data.keys.toSet(), {..._ruleKeys, 'reportedAt'});
      },
    );

    test(
      'skips an identical report within the throttle window, unless forced',
      () async {
        expect(
          await reporter().report(permission: SmsAvailability.granted),
          isTrue,
        );
        now = now.add(const Duration(seconds: 30));
        expect(
          await reporter().report(permission: SmsAvailability.granted),
          isFalse,
        );
        expect(
          await reporter().report(
            permission: SmsAvailability.granted,
            force: true,
          ),
          isTrue,
        );
        now = now.add(const Duration(minutes: 3));
        expect(
          await reporter().report(permission: SmsAvailability.granted),
          isTrue,
        );
      },
    );

    test(
      'stops reporting once the server refuses (disconnected or replaced)',
      () async {
        expect(
          await reporter(
            db: _DenyingFirestore(),
          ).report(permission: SmsAvailability.granted),
          isFalse,
        );
        expect(savedUids, [null]);
        expect(
          await reporter().report(permission: SmsAvailability.granted),
          isFalse,
        );
      },
    );
  });
}
