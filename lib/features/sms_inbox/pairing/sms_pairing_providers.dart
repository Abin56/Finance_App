import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sms_device_presence.dart';
import 'sms_device_status_reporter.dart';
import 'sms_pairing_link.dart';
import 'sms_pairing_service.dart';

/// App-lifetime holder for a scanned pairing token while the router's gates
/// (onboarding, sign-in, lock, setup) run first. A plain object, not Riverpod
/// state, because the router's `redirect` writes it.
final pendingSmsPairingProvider = Provider<PendingSmsPairing>(
  (ref) => PendingSmsPairing(),
);

final smsPairingServiceProvider = Provider<SmsPairingService>(
  (ref) => SmsPairingService(),
);

final smsDeviceStatusReporterProvider = Provider<SmsDeviceStatusReporter>(
  (ref) => SmsDeviceStatusReporter(),
);

final smsDevicePresenceReporterProvider = Provider<SmsDevicePresenceReporter>(
  (ref) => SmsDevicePresenceReporter(),
);

/// The account this install is paired to (local flag), re-read on demand.
final smsPairedUidProvider = FutureProvider.autoDispose<String?>(
  (ref) => readSmsPairedUid(),
);
