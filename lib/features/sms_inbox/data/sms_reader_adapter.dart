import 'dart:io';

import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

import '../domain/raw_sms_message.dart';

/// Wraps `flutter_sms_inbox` behind the feature's own [RawSmsMessage] type
/// so the plugin's type never leaks past this one file. On iOS (or any
/// non-Android platform) this returns an empty list immediately — there is
/// no public SMS-reading API to call, so no platform channel is touched.
class SmsReaderAdapter {
  const SmsReaderAdapter();

  static const int _maxScanCount = 500;

  Future<List<RawSmsMessage>> readInbox() async {
    if (!Platform.isAndroid) return const [];

    final messages = await SmsQuery().querySms(count: _maxScanCount, kinds: const [SmsQueryKind.inbox]);

    return messages
        .where((m) => m.address != null && m.body != null && m.date != null)
        .map(
          (m) => RawSmsMessage(address: m.address!, body: m.body!, date: m.date!, threadId: m.threadId),
        )
        .toList();
  }
}
