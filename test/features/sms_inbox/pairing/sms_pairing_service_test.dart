import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_pairing_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_abcde';
const _device = '0b5a3f4e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';

FirebaseFunctionsException _refusal(String code, String reason) =>
    FirebaseFunctionsException(
      message: 'refused',
      code: code,
      details: {'reason': reason},
    );

class _Calls {
  final List<(String, Map<String, Object?>)> log = [];
  Object? Function(String name, Map<String, Object?> data) respond = (_, _) =>
      const {};

  Future<Object?> call(String name, Map<String, Object?> data) async {
    log.add((name, data));
    return respond(name, data);
  }
}

void main() {
  late _Calls calls;
  late List<String?> savedUids;

  SmsPairingService service({
    String? installId = _device,
    String? label = 'Pixel 8',
  }) => SmsPairingService(
    call: calls.call,
    installId: () async => installId,
    deviceLabel: () async => label,
    savePairedUid: (uid) async => savedUids.add(uid),
    appVersion: '1.0.0+1',
  );

  setUp(() {
    calls = _Calls();
    savedUids = [];
  });

  test(
    'preview sends the token and this install id, and reads the phone it would replace',
    () async {
      calls.respond = (_, _) => {
        'expiresAt': 1761400000000,
        'activeDevice': {
          'label': 'Old phone',
          'isThisDevice': false,
          'pairedAt': 1761300000000,
        },
      };
      final preview = await service().preview(_token);
      expect(calls.log.single.$1, 'previewSmsPairingCallable');
      expect(calls.log.single.$2, {'token': _token, 'deviceId': _device});
      expect(preview.replacesAnotherPhone, isTrue);
      expect(preview.activeDevice!.label, 'Old phone');
    },
  );

  test(
    'approve sends device details and records the paired account locally only after success',
    () async {
      calls.respond = (_, _) => {
        'status': 'paired',
        'alreadyPaired': false,
        'replacedDeviceLabel': null,
      };
      final approval = await service().approve(_token, uid: 'uid-1');
      expect(calls.log.single.$1, 'approveSmsPairingCallable');
      expect(calls.log.single.$2, {
        'token': _token,
        'deviceId': _device,
        'deviceLabel': 'Pixel 8',
        'appVersion': '1.0.0+1',
      });
      expect(approval.alreadyPaired, isFalse);
      expect(savedUids, ['uid-1']);
    },
  );

  test('a refused approval records nothing locally', () async {
    calls.respond = (_, _) =>
        throw _refusal('permission-denied', 'wrong_account');
    await expectLater(
      service().approve(_token, uid: 'uid-1'),
      throwsA(
        isA<SmsPairingException>().having(
          (e) => e.failure,
          'failure',
          SmsPairingFailure.wrongAccount,
        ),
      ),
    );
    expect(savedUids, isEmpty);
  });

  test('an unreadable install id never reaches the server', () async {
    await expectLater(
      service(installId: null).approve(_token, uid: 'uid-1'),
      throwsA(
        isA<SmsPairingException>().having(
          (e) => e.failure,
          'failure',
          SmsPairingFailure.invalidDevice,
        ),
      ),
    );
    expect(calls.log, isEmpty);
  });

  test('cancel sends only the token', () async {
    await service().cancel(_token);
    expect(calls.log.single.$1, 'cancelSmsPairingCallable');
    expect(calls.log.single.$2, {'token': _token});
  });

  test(
    'disconnect revokes this install and clears the local flag; already-gone counts as done',
    () async {
      await service().disconnectThisDevice();
      expect(calls.log.single.$1, 'revokeSmsDeviceCallable');
      expect(calls.log.single.$2, {'deviceId': _device});
      expect(savedUids, [null]);

      calls.respond = (_, _) => throw _refusal('not-found', 'not_found');
      await service().disconnectThisDevice();
      expect(savedUids, [null, null]);
    },
  );

  group('classifySmsPairingError', () {
    test('uses the server reason code, never the message', () {
      expect(
        classifySmsPairingError(_refusal('deadline-exceeded', 'expired')),
        SmsPairingFailure.expired,
      );
      expect(
        classifySmsPairingError(_refusal('already-exists', 'used')),
        SmsPairingFailure.used,
      );
      expect(
        classifySmsPairingError(_refusal('unavailable', 'sync_suspended')),
        SmsPairingFailure.syncSuspended,
      );
      expect(
        classifySmsPairingError(_refusal('failed-precondition', 'superseded')),
        SmsPairingFailure.superseded,
      );
      expect(
        classifySmsPairingError(_refusal('internal', 'something_new')),
        SmsPairingFailure.unknown,
      );
    });

    test('maps transport failures without a reason', () {
      expect(
        classifySmsPairingError(
          FirebaseFunctionsException(message: 'x', code: 'unavailable'),
        ),
        SmsPairingFailure.offline,
      );
      expect(
        classifySmsPairingError(
          FirebaseFunctionsException(message: 'x', code: 'unauthenticated'),
        ),
        SmsPairingFailure.unauthenticated,
      );
      expect(
        classifySmsPairingError(TimeoutException('slow')),
        SmsPairingFailure.offline,
      );
      expect(
        classifySmsPairingError(StateError('?')),
        SmsPairingFailure.unknown,
      );
    });

    test('only transient failures are retryable with the same code', () {
      expect(SmsPairingFailure.offline.retryable, isTrue);
      expect(SmsPairingFailure.expired.retryable, isFalse);
      expect(SmsPairingFailure.used.retryable, isFalse);
      expect(SmsPairingFailure.wrongAccount.retryable, isFalse);
    });
  });
}
