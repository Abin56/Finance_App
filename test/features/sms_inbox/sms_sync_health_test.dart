import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/background/sms_background_entry.dart';
import 'package:finance_app/features/sms_inbox/background/sms_background_scan.dart';
import 'package:finance_app/features/sms_inbox/background/sms_background_upload_switch.dart';
import 'package:finance_app/features/sms_inbox/data/sms_sync_diagnostics_store.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_sync_diagnostics.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_sync_health.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t0 = DateTime(2026, 10, 25, 9);
final _t1 = DateTime(2026, 10, 25, 10);
const _uid = 'uid-secret-123';
const _device = 'device-secret-456';

SmsBackgroundScanResult _scanOk({
  String? uploadError,
  SmsSyncFailureCategory? failure,
}) => SmsBackgroundScanResult.success(
  1,
  uploadError: uploadError,
  uploadFailure: failure,
);

FirebaseException _fe(String code, {String? message}) =>
    FirebaseException(plugin: 'cloud_firestore', code: code, message: message);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('classifySmsSyncFailure — categories only, never message text', () {
    test('maps known failures', () {
      expect(
        classifySmsSyncFailure(TimeoutException('x')),
        SmsSyncFailureCategory.timeout,
      );
      expect(
        classifySmsSyncFailure(_fe('permission-denied')),
        SmsSyncFailureCategory.permissionDenied,
      );
      expect(
        classifySmsSyncFailure(_fe('unauthenticated')),
        SmsSyncFailureCategory.authUnavailable,
      );
      expect(
        classifySmsSyncFailure(_fe('unavailable')),
        SmsSyncFailureCategory.offline,
      );
      expect(
        classifySmsSyncFailure(_fe('deadline-exceeded')),
        SmsSyncFailureCategory.timeout,
      );
      expect(
        classifySmsSyncFailure(StateError('boom')),
        SmsSyncFailureCategory.unknown,
      );
    });

    test('never carries the exception message', () {
      final c = classifySmsSyncFailure(
        _fe(
          'permission-denied',
          message: 'users/$_uid/smsTransactionCandidates HDFC 4242 Rs 500',
        ),
      );
      final text = '${c.code} ${c.label}';
      expect(text, isNot(contains(_uid)));
      expect(text, isNot(contains('HDFC')));
      expect(text, isNot(contains('4242')));
    });
  });

  group('SmsSyncDiagnostics.applyRun', () {
    test('local scan success is independent of upload failure', () {
      final d = const SmsSyncDiagnostics()
          .applyAttempt(_t0)
          .applyRun(
            now: _t1,
            scanSucceeded: true,
            cloudControlled: true,
            gateState: SmsCloudSyncState.enabled,
            uploadRan: true,
            uploadFailure: SmsSyncFailureCategory.offline,
          );
      expect(d.lastAttemptAt, _t0);
      expect(d.lastScanSuccessAt, _t1);
      expect(d.lastUploadSuccessAt, isNull);
      expect(d.lastUploadFailure, SmsSyncFailureCategory.offline);
      expect(d.consecutiveUploadFailures, 1);
    });

    test('zero-write run with not-owned candidates is not an upload success', () {
      var d = const SmsSyncDiagnostics().applyRun(
        now: _t0,
        scanSucceeded: true,
        cloudControlled: true,
        gateState: SmsCloudSyncState.enabled,
        uploadRan: true,
        uploaded: 2,
      );
      expect(d.lastUploadSuccessAt, _t0);

      d = d.applyRun(
        now: _t1,
        scanSucceeded: true,
        cloudControlled: true,
        gateState: SmsCloudSyncState.enabled,
        uploadRan: true,
        uploaded: 0,
        skippedNotOwned: 117,
      );
      expect(d.lastUploadSuccessAt, _t0); // not advanced
      expect(d.lastUploadSkippedNotOwned, 117);
      expect(d.consecutiveUploadFailures, 0);

      final health = describeSmsSyncHealth(d);
      expect(health.uploadNote, contains('117 pending messages'));
      expect(health.uploadNoteIsError, isTrue);
    });

    test('nothing pending at all is still a clean upload success', () {
      final d = const SmsSyncDiagnostics().applyRun(
        now: _t1,
        scanSucceeded: true,
        cloudControlled: true,
        gateState: SmsCloudSyncState.enabled,
        uploadRan: true,
      );
      expect(d.lastUploadSuccessAt, _t1);
      expect(d.lastUploadSkippedNotOwned, 0);
    });

    test('upload success resets failures; scan failure keeps last success', () {
      var d = const SmsSyncDiagnostics().applyRun(
        now: _t0,
        scanSucceeded: true,
        cloudControlled: true,
        gateState: SmsCloudSyncState.enabled,
        uploadRan: true,
        uploadFailure: SmsSyncFailureCategory.timeout,
      );
      d = d.applyRun(
        now: _t1,
        scanSucceeded: true,
        cloudControlled: true,
        gateState: SmsCloudSyncState.enabled,
        uploadRan: true,
      );
      expect(d.lastUploadSuccessAt, _t1);
      expect(d.lastUploadFailure, isNull);
      expect(d.consecutiveUploadFailures, 0);

      d = d.applyRun(
        now: DateTime(2026, 10, 25, 11),
        scanSucceeded: false,
        scanError: 'permission',
        cloudControlled: true,
      );
      expect(d.lastScanSuccessAt, _t1); // unchanged
      expect(d.lastScanError, 'permission');
      expect(d.cloudState, SmsCloudSyncState.enabled); // untouched
    });

    test('retry exhausted after repeated upload failures', () {
      var d = const SmsSyncDiagnostics();
      for (var i = 0; i < SmsSyncDiagnostics.retryExhaustedThreshold; i++) {
        expect(d.uploadRetryExhausted, isFalse);
        d = d.applyRun(
          now: _t0,
          scanSucceeded: true,
          cloudControlled: true,
          gateState: SmsCloudSyncState.enabled,
          uploadRan: true,
          uploadFailure: SmsSyncFailureCategory.permissionDenied,
        );
      }
      expect(d.uploadRetryExhausted, isTrue);
      expect(
        describeSmsSyncHealth(d).uploadNote,
        contains('failed 5 times in a row'),
      );
    });

    test(
      'unverified gate records the category and counts no upload failure',
      () {
        final d = const SmsSyncDiagnostics().applyRun(
          now: _t0,
          scanSucceeded: true,
          cloudControlled: true,
          gateState: SmsCloudSyncState.unverified,
          gateFailure: SmsSyncFailureCategory.authUnavailable,
        );
        expect(d.cloudState, SmsCloudSyncState.unverified);
        expect(d.cloudUnverifiedReason, SmsSyncFailureCategory.authUnavailable);
        expect(d.consecutiveUploadFailures, 0);
        // Recovering to disabled clears the stale reason.
        final back = d.applyRun(
          now: _t1,
          scanSucceeded: true,
          cloudControlled: true,
          gateState: SmsCloudSyncState.disabled,
        );
        expect(back.cloudUnverifiedReason, isNull);
      },
    );

    test('build without the runtime switch reports Disabled', () {
      final d = const SmsSyncDiagnostics().applyRun(
        now: _t0,
        scanSucceeded: true,
        cloudControlled: false,
      );
      expect(d.cloudState, SmsCloudSyncState.disabled);
    });
  });

  group('describeSmsSyncHealth', () {
    test('four states, distinct wording', () {
      final unchecked = describeSmsSyncHealth(const SmsSyncDiagnostics());
      expect(unchecked.cloudLabel, 'Not checked yet');
      expect(unchecked.showUploadRow, isFalse);

      expect(
        describeSmsSyncHealth(
          const SmsSyncDiagnostics(cloudState: SmsCloudSyncState.disabled),
        ).cloudLabel,
        'Off',
      );
      final unverified = describeSmsSyncHealth(
        const SmsSyncDiagnostics(
          cloudState: SmsCloudSyncState.unverified,
          cloudUnverifiedReason: SmsSyncFailureCategory.offline,
        ),
      );
      expect(unverified.cloudLabel, "Can't verify");
      expect(unverified.cloudNote, contains('no connection'));
      expect(unverified.cloudNote, contains('nothing is uploaded'));

      final enabled = describeSmsSyncHealth(
        SmsSyncDiagnostics(
          cloudState: SmsCloudSyncState.enabled,
          lastUploadSuccessAt: _t0,
        ),
      );
      expect(enabled.cloudLabel, 'On');
      expect(enabled.showUploadRow, isTrue);
      expect(enabled.lastUploadSuccessAt, _t0);
    });

    test('native last success is only a fallback for the scan time', () {
      expect(
        describeSmsSyncHealth(
          const SmsSyncDiagnostics(),
          nativeLastSuccessAt: _t0,
        ).lastScanSuccessAt,
        _t0,
      );
      expect(
        describeSmsSyncHealth(
          SmsSyncDiagnostics(lastScanSuccessAt: _t1),
          nativeLastSuccessAt: _t0,
        ).lastScanSuccessAt,
        _t1,
      );
    });
  });

  group('SmsSyncDiagnosticsStore', () {
    test('round-trips and holds no uid/device id/content', () async {
      SharedPreferences.setMockInitialValues({
        // Present in prefs from F3 — must never be copied into diagnostics.
        kSmsBackgroundInstallIdPrefsKey: _device,
      });
      const store = SmsSyncDiagnosticsStore();
      await store.update((d) => d.applyAttempt(_t0));
      await store.update(
        (d) => d.applyRun(
          now: _t1,
          scanSucceeded: true,
          cloudControlled: true,
          gateState: SmsCloudSyncState.enabled,
          uploadRan: true,
          uploadFailure: SmsSyncFailureCategory.timeout,
        ),
      );
      final read = await store.read();
      expect(read.lastAttemptAt, _t0);
      expect(read.lastScanSuccessAt, _t1);
      expect(read.cloudState, SmsCloudSyncState.enabled);
      expect(read.lastUploadFailure, SmsSyncFailureCategory.timeout);
      expect(read.consecutiveUploadFailures, 1);

      final prefs = await SharedPreferences.getInstance();
      final diagValues = [
        for (final k in prefs.getKeys().where(
          (k) => k.startsWith('sms_sync_diag_'),
        ))
          '$k=${prefs.get(k)}',
      ].join('\n');
      expect(diagValues, isNotEmpty);
      expect(diagValues, isNot(contains(_uid)));
      expect(diagValues, isNot(contains(_device)));
    });

    test('empty storage reads as a blank record', () async {
      SharedPreferences.setMockInitialValues({});
      final d = await const SmsSyncDiagnosticsStore().read();
      expect(d.lastAttemptAt, isNull);
      expect(d.cloudState, isNull);
      expect(d.consecutiveUploadFailures, 0);
    });
  });

  group('SmsBackgroundUploadSwitch.check — disabled vs unverified', () {
    Future<FakeFirebaseFirestore> fs(Map<String, Object?>? cfg) async {
      final f = FakeFirebaseFirestore();
      if (cfg != null) {
        await f
            .collection('users')
            .doc('u')
            .collection('smsSyncConfig')
            .doc('backgroundUpload')
            .set(cfg);
      }
      return f;
    }

    SmsBackgroundUploadSwitch sw(FakeFirebaseFirestore f) =>
        SmsBackgroundUploadSwitch(
          firestore: () => f,
          installId: () async => 'i',
        );

    test(
      'no document and mismatched device are DISABLED (read fine)',
      () async {
        expect(
          (await sw(await fs(null)).check('u')).state,
          SmsCloudSyncState.disabled,
        );
        expect(
          (await sw(
            await fs({'enabled': true, 'deviceId': 'x'}),
          ).check('u')).state,
          SmsCloudSyncState.disabled,
        );
      },
    );

    test('matching document is ENABLED', () async {
      final d = await sw(
        await fs({'enabled': true, 'deviceId': 'i'}),
      ).check('u');
      expect(d.state, SmsCloudSyncState.enabled);
      expect(d.failure, isNull);
    });

    test(
      'read failures are UNVERIFIED with a category (never enabled)',
      () async {
        SmsBackgroundUploadSwitch thrower(Object e) =>
            SmsBackgroundUploadSwitch(
              firestore: () => throw e,
              installId: () async => 'i',
            );
        final denied = await thrower(_fe('permission-denied')).check('u');
        expect(denied.state, SmsCloudSyncState.unverified);
        expect(denied.failure, SmsSyncFailureCategory.permissionDenied);

        final offline = await thrower(_fe('unavailable')).check('u');
        expect(offline.failure, SmsSyncFailureCategory.offline);

        final timeout = await thrower(TimeoutException('t')).check('u');
        expect(timeout.failure, SmsSyncFailureCategory.timeout);

        final blank = await sw(FakeFirebaseFirestore()).check('');
        expect(blank.state, SmsCloudSyncState.unverified);
        expect(blank.failure, SmsSyncFailureCategory.authUnavailable);
        expect(await thrower(StateError('x')).isEnabledFor('u'), isFalse);
      },
    );
  });

  group('background gate + run diagnostics (F3 fail-closed preserved)', () {
    test('signed out → unverified/auth_unavailable, no uid', () async {
      final gate = await resolveBackgroundUploadGate(uidResolver: () => null);
      expect(gate.uid, isNull);
      expect(gate.state, SmsCloudSyncState.unverified);
      expect(gate.failure, SmsSyncFailureCategory.authUnavailable);
    });

    test('uid is exposed only when enabled', () async {
      final f = FakeFirebaseFirestore();
      final sw = SmsBackgroundUploadSwitch(
        firestore: () => f,
        installId: () async => 'i',
      );
      expect(
        (await resolveBackgroundUploadGate(
          uidResolver: () => 'u',
          uploadSwitch: sw,
        )).uid,
        isNull,
      );
      await f
          .collection('users')
          .doc('u')
          .collection('smsSyncConfig')
          .doc('backgroundUpload')
          .set({'enabled': true, 'deviceId': 'i'});
      final on = await resolveBackgroundUploadGate(
        uidResolver: () => 'u',
        uploadSwitch: sw,
      );
      expect(on.uid, 'u');
      expect(on.state, SmsCloudSyncState.enabled);
    });

    test('upload counts as run only when the gate authorized a uid', () {
      const enabledGate = SmsUploadGate(
        uid: 'u',
        state: SmsCloudSyncState.enabled,
      );
      final ok = applyBackgroundRunDiagnostics(
        const SmsSyncDiagnostics(),
        now: _t0,
        result: _scanOk(),
        gate: enabledGate,
        cloudControlled: true,
      );
      expect(ok.lastUploadSuccessAt, _t0);

      final failed = applyBackgroundRunDiagnostics(
        const SmsSyncDiagnostics(),
        now: _t0,
        result: _scanOk(
          uploadError: 'upload_failed',
          failure: SmsSyncFailureCategory.permissionDenied,
        ),
        gate: enabledGate,
        cloudControlled: true,
      );
      expect(failed.lastUploadFailure, SmsSyncFailureCategory.permissionDenied);
      expect(failed.lastScanSuccessAt, _t0);

      final disabled = applyBackgroundRunDiagnostics(
        const SmsSyncDiagnostics(),
        now: _t0,
        result: _scanOk(),
        gate: const SmsUploadGate(state: SmsCloudSyncState.disabled),
        cloudControlled: true,
      );
      expect(disabled.cloudState, SmsCloudSyncState.disabled);
      expect(disabled.lastUploadSuccessAt, isNull);
    });
  });

  test('scan result exposes the failure category, not the exception', () {
    final map = SmsBackgroundScanResult.success(
      0,
      uploadError: 'upload_failed',
      uploadFailure: SmsSyncFailureCategory.offline,
    ).toMap();
    expect(map['uploadFailure'], 'offline');
    expect(map['uploadError'], 'upload_failed');
  });
}
