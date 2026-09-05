import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

import '../domain/raw_sms_message.dart';
import '../domain/sms_message_source.dart';
import '../domain/sms_read_exception.dart';

/// Wraps `flutter_sms_inbox` behind the feature's own [RawSmsMessage] type
/// so the plugin's type never leaks past this one file. On iOS (or any
/// non-Android platform) this returns an empty list immediately — there is
/// no public SMS-reading API to call, so no platform channel is touched.
class SmsReaderAdapter {
  const SmsReaderAdapter();

  static const int _maxScanCount = 500;

  Future<List<RawSmsMessage>> readInbox() async {
    if (!Platform.isAndroid) return const [];

    final List<SmsMessage> messages;
    try {
      messages = await SmsQuery().querySms(
        count: _maxScanCount,
        kinds: const [SmsQueryKind.inbox],
      );
    } on PlatformException catch (e) {
      // The plugin's native side catches SecurityException itself and reports
      // it as this specific error code (see SmsQueryHandler.handle in
      // flutter_sms_inbox) — it does not surface as an uncaught crash, and an
      // empty successful result is indistinguishable from "genuinely no SMS"
      // without catching this explicitly. This is the exact failure mode a
      // release build missing READ_SMS (or an OS/OEM permission revocation)
      // produces, so it must never be swallowed into an empty list.
      if (e.code == 'permission_denied') {
        throw const SmsPermissionUnavailableException();
      }
      throw SmsQueryFailedException(e.message ?? e.code);
    }

    return messages
        .where((m) => m.address != null && m.body != null && m.date != null)
        .map(
          (m) => RawSmsMessage(
            address: m.address!,
            body: m.body!,
            date: m.date!,
            source: SmsMessageSource.deviceSms,
            threadId: m.threadId,
          ),
        )
        .toList();
  }
}
