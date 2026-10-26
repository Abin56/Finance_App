import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_app/features/sms_inbox/background/sms_background_entry.dart';
import 'package:finance_app/features/sms_inbox/background/sms_background_upload_switch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'uid-owner';
const _otherUid = 'uid-other';
const _install = 'install-abc';

/// A Firestore whose reads always fail — stands in for offline / permission
/// denied / no server reachable (the switch reads from the SERVER only).
class _FailingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
}

Future<FakeFirebaseFirestore> _firestoreWith(
  Map<String, Object?>? config, {
  String uid = _uid,
}) async {
  final firestore = FakeFirebaseFirestore();
  if (config != null) {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('smsSyncConfig')
        .doc('backgroundUpload')
        .set(config);
  }
  return firestore;
}

SmsBackgroundUploadSwitch _switchFor(
  FakeFirebaseFirestore firestore, {
  String? installId = _install,
  Duration timeout = const Duration(seconds: 5),
}) => SmsBackgroundUploadSwitch(
  firestore: () => firestore,
  installId: () async => installId,
  timeout: timeout,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmsBackgroundUploadSwitch — default OFF / fail closed', () {
    test('no config document → OFF (the default for every account)', () async {
      final sw = _switchFor(await _firestoreWith(null));
      expect(await sw.isEnabledFor(_uid), isFalse);
    });

    test(
      'enabled:true + matching deviceId → ON for exactly that uid',
      () async {
        final sw = _switchFor(
          await _firestoreWith({'enabled': true, 'deviceId': _install}),
        );
        expect(await sw.isEnabledFor(_uid), isTrue);
      },
    );

    test('enabled:false → OFF (disable without rebuilding the APK)', () async {
      final sw = _switchFor(
        await _firestoreWith({'enabled': false, 'deviceId': _install}),
      );
      expect(await sw.isEnabledFor(_uid), isFalse);
    });

    test('a different registered device stays OFF', () async {
      final sw = _switchFor(
        await _firestoreWith({'enabled': true, 'deviceId': 'some-other-phone'}),
      );
      expect(await sw.isEnabledFor(_uid), isFalse);
    });

    test('missing deviceId → OFF (no "all devices" wildcard)', () async {
      final sw = _switchFor(await _firestoreWith({'enabled': true}));
      expect(await sw.isEnabledFor(_uid), isFalse);
    });

    test('wrong field types are OFF, never coerced to ON', () async {
      for (final bad in <Map<String, Object?>>[
        {'enabled': 'true', 'deviceId': _install},
        {'enabled': 1, 'deviceId': _install},
        {'enabled': true, 'deviceId': 123},
        {'enabled': null, 'deviceId': _install},
      ]) {
        final sw = _switchFor(await _firestoreWith(bad));
        expect(await sw.isEnabledFor(_uid), isFalse, reason: '$bad');
      }
    });

    test(
      'UID isolation: another account does not inherit the switch',
      () async {
        final sw = _switchFor(
          await _firestoreWith({'enabled': true, 'deviceId': _install}),
        );
        expect(await sw.isEnabledFor(_uid), isTrue);
        expect(await sw.isEnabledFor(_otherUid), isFalse);
        expect(await sw.isEnabledFor(''), isFalse);
      },
    );

    test('unreadable install id → OFF', () async {
      final firestore = await _firestoreWith({
        'enabled': true,
        'deviceId': _install,
      });
      expect(
        await _switchFor(firestore, installId: null).isEnabledFor(_uid),
        isFalse,
      );
      expect(
        await _switchFor(firestore, installId: '  ').isEnabledFor(_uid),
        isFalse,
      );
    });

    test(
      'Firestore read failure → OFF (never throws, no cached "last good")',
      () async {
        final sw = SmsBackgroundUploadSwitch(
          firestore: () => _FailingFirestore(),
          installId: () async => _install,
        );
        expect(await sw.isEnabledFor(_uid), isFalse);
      },
    );

    test('Firebase not initialized (factory throws) → OFF', () async {
      final sw = SmsBackgroundUploadSwitch(
        firestore: () => throw StateError('[core/no-app]'),
        installId: () async => _install,
      );
      expect(await sw.isEnabledFor(_uid), isFalse);
    });

    test('install-id lookup throwing → OFF', () async {
      final sw = SmsBackgroundUploadSwitch(
        firestore: () => FakeFirebaseFirestore(),
        installId: () => throw StateError('prefs unavailable'),
      );
      expect(await sw.isEnabledFor(_uid), isFalse);
    });
  });

  group('getOrCreateSmsSyncInstallId', () {
    test(
      'creates a random id once and returns the same id afterwards',
      () async {
        SharedPreferences.setMockInitialValues({});
        final first = await getOrCreateSmsSyncInstallId();
        final second = await getOrCreateSmsSyncInstallId();
        expect(first, isNotNull);
        expect(first, second);
        expect(first!.length, greaterThanOrEqualTo(32));
      },
    );

    test('reuses an existing stored id', () async {
      SharedPreferences.setMockInitialValues({
        kSmsBackgroundInstallIdPrefsKey: 'stored-id',
      });
      expect(await getOrCreateSmsSyncInstallId(), 'stored-id');
    });

    test('is not derived from the uid or any SMS data', () async {
      SharedPreferences.setMockInitialValues({});
      final id = await getOrCreateSmsSyncInstallId();
      expect(id, isNot(contains(_uid)));
    });
  });

  group('resolveBackgroundUploadUid — the entry-point gate', () {
    test('signed out → null, and the switch is never consulted', () async {
      var consulted = false;
      final sw = SmsBackgroundUploadSwitch(
        firestore: () {
          consulted = true;
          return FakeFirebaseFirestore();
        },
        installId: () async => _install,
      );
      final uid = await resolveBackgroundUploadUid(
        uidResolver: () => null,
        uploadSwitch: sw,
      );
      expect(uid, isNull);
      expect(consulted, isFalse);
    });

    test('signed in but switch OFF → null (default)', () async {
      final uid = await resolveBackgroundUploadUid(
        uidResolver: () => _uid,
        uploadSwitch: _switchFor(await _firestoreWith(null)),
      );
      expect(uid, isNull);
    });

    test('signed in + authorized → that uid only', () async {
      final uid = await resolveBackgroundUploadUid(
        uidResolver: () => _uid,
        uploadSwitch: _switchFor(
          await _firestoreWith({'enabled': true, 'deviceId': _install}),
        ),
      );
      expect(uid, _uid);
    });

    test(
      'signed in as a different account than the authorized one → null',
      () async {
        final uid = await resolveBackgroundUploadUid(
          uidResolver: () => _otherUid,
          uploadSwitch: _switchFor(
            await _firestoreWith({'enabled': true, 'deviceId': _install}),
          ),
        );
        expect(uid, isNull);
      },
    );

    test('a throwing resolver or switch → null, never an exception', () async {
      expect(
        await resolveBackgroundUploadUid(
          uidResolver: () => throw StateError('auth unavailable'),
        ),
        isNull,
      );
      final throwing = SmsBackgroundUploadSwitch(
        firestore: () => throw StateError('no app'),
        installId: () async => _install,
      );
      expect(
        await resolveBackgroundUploadUid(
          uidResolver: () => _uid,
          uploadSwitch: throwing,
        ),
        isNull,
      );
    });
  });

  group(
    'SmsBackgroundUploadSwitch — operator kill switches (SMS Sync pairing)',
    () {
      Future<FakeFirebaseFirestore> paired() =>
          _firestoreWith({'enabled': true, 'deviceId': _install});

      test(
        'the global emergency switch turns uploads OFF even for the paired device',
        () async {
          final firestore = await paired();
          await firestore.collection('smsSyncControl').doc('global').set({
            'uploadsDisabled': true,
          });
          expect(await _switchFor(firestore).isEnabledFor(_uid), isFalse);
          final decision = await _switchFor(firestore).check(_uid);
          expect(decision.state.name, 'disabled');
        },
      );

      test('a per-account operator hold turns uploads OFF', () async {
        final firestore = await paired();
        await firestore
            .collection('users')
            .doc(_uid)
            .collection('smsSyncConfig')
            .doc('operatorHold')
            .set({'disabled': true});
        expect(await _switchFor(firestore).isEnabledFor(_uid), isFalse);
      });

      test(
        'switch documents present but not set leave the paired device ON',
        () async {
          final firestore = await paired();
          await firestore.collection('smsSyncControl').doc('global').set({
            'uploadsDisabled': false,
          });
          await firestore
              .collection('users')
              .doc(_uid)
              .collection('smsSyncConfig')
              .doc('operatorHold')
              .set({'note': 'released'});
          expect(await _switchFor(firestore).isEnabledFor(_uid), isTrue);
        },
      );

      test("another account's hold doesn't affect this one", () async {
        final firestore = await paired();
        await firestore
            .collection('users')
            .doc(_otherUid)
            .collection('smsSyncConfig')
            .doc('operatorHold')
            .set({'disabled': true});
        expect(await _switchFor(firestore).isEnabledFor(_uid), isTrue);
      });
    },
  );
}
