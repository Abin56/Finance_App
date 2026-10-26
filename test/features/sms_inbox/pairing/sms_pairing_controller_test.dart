import 'package:cloud_functions/cloud_functions.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_sync_diagnostics.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_device_status_reporter.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_pairing_controller.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_pairing_providers.dart';
import 'package:finance_app/features/sms_inbox/pairing/sms_pairing_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_abcde';
const _device = '0b5a3f4e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';

void main() {
  late List<String> calledNames;
  late Object? Function(String name) respond;
  late List<String?> savedUids;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        smsPairingServiceProvider.overrideWithValue(
          SmsPairingService(
            call: (name, data) async {
              calledNames.add(name);
              return respond(name);
            },
            installId: () async => _device,
            deviceLabel: () async => 'Pixel 8',
            savePairedUid: (uid) async => savedUids.add(uid),
          ),
        ),
        // Reporting is covered by its own suite; here it's a no-op (not paired).
        smsDeviceStatusReporterProvider.overrideWithValue(
          SmsDeviceStatusReporter(
            currentUid: () => 'uid-1',
            pairedUid: () async => null,
            installId: () async => _device,
            diagnostics: () async => const SmsSyncDiagnostics(),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    calledNames = [];
    savedUids = [];
    respond = (name) => switch (name) {
      'previewSmsPairingCallable' => {
        'expiresAt': 1761400000000,
        'activeDevice': null,
      },
      'approveSmsPairingCallable' => {
        'status': 'paired',
        'alreadyPaired': false,
      },
      _ => const {},
    };
  });

  test('without a scanned code there is nothing to approve', () async {
    final c = container();
    c.listen(smsPairingControllerProvider, (_, _) {});
    await c.read(smsPairingControllerProvider.notifier).start();
    expect(c.read(smsPairingControllerProvider), isA<SmsPairingNoCode>());
    expect(calledNames, isEmpty);
  });

  test('preview → explicit approve → paired; the code is consumed', () async {
    final c = container();
    c.listen(smsPairingControllerProvider, (_, _) {});
    c.read(pendingSmsPairingProvider).offer(_token);
    final controller = c.read(smsPairingControllerProvider.notifier);

    await controller.start();
    expect(c.read(smsPairingControllerProvider), isA<SmsPairingReady>());
    expect(calledNames, ['previewSmsPairingCallable']);

    await controller.approve(uid: 'uid-1');
    expect(c.read(smsPairingControllerProvider), isA<SmsPairingPaired>());
    expect(calledNames, [
      'previewSmsPairingCallable',
      'approveSmsPairingCallable',
    ]);
    expect(savedUids, ['uid-1']);
    expect(c.read(pendingSmsPairingProvider).hasToken, isFalse);
  });

  test(
    'a wrong-account code fails at preview and keeps the code for after switching account',
    () async {
      respond = (_) => throw FirebaseFunctionsException(
        message: 'x',
        code: 'permission-denied',
        details: {'reason': 'wrong_account'},
      );
      final c = container();
      c.listen(smsPairingControllerProvider, (_, _) {});
      c.read(pendingSmsPairingProvider).offer(_token);
      await c.read(smsPairingControllerProvider.notifier).start();
      final state = c.read(smsPairingControllerProvider);
      expect(
        state,
        isA<SmsPairingFailed>().having(
          (s) => s.failure,
          'failure',
          SmsPairingFailure.wrongAccount,
        ),
      );
      expect(c.read(pendingSmsPairingProvider).hasToken, isTrue);
    },
  );

  test('an offline approval can be retried without re-scanning', () async {
    final c = container();
    c.listen(smsPairingControllerProvider, (_, _) {});
    c.read(pendingSmsPairingProvider).offer(_token);
    final controller = c.read(smsPairingControllerProvider.notifier);
    await controller.start();

    respond = (_) =>
        throw FirebaseFunctionsException(message: 'x', code: 'unavailable');
    await controller.approve(uid: 'uid-1');
    expect(
      c.read(smsPairingControllerProvider),
      isA<SmsPairingFailed>().having(
        (s) => s.failure,
        'failure',
        SmsPairingFailure.offline,
      ),
    );

    await controller.retry();
    expect(c.read(smsPairingControllerProvider), isA<SmsPairingReady>());
    respond = (_) => {'status': 'paired', 'alreadyPaired': true};
    await controller.approve(uid: 'uid-1');
    expect(c.read(smsPairingControllerProvider), isA<SmsPairingPaired>());
  });

  test(
    '"Not now" cancels the code on the server and forgets it locally',
    () async {
      final c = container();
      c.listen(smsPairingControllerProvider, (_, _) {});
      c.read(pendingSmsPairingProvider).offer(_token);
      final controller = c.read(smsPairingControllerProvider.notifier);
      await controller.start();
      await controller.cancel();
      expect(calledNames.last, 'cancelSmsPairingCallable');
      expect(c.read(smsPairingControllerProvider), isA<SmsPairingCanceled>());
      expect(c.read(pendingSmsPairingProvider).hasToken, isFalse);
      expect(savedUids, isEmpty);
    },
  );
}
