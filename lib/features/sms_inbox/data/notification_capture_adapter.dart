import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/raw_sms_message.dart';
import '../domain/sms_message_source.dart';

/// Wraps the native `finance_app/notification_listener` method channel's
/// `getCaptured` call behind [RawSmsMessage] — the same shape
/// `SmsReaderAdapter` returns for the device SMS provider — so
/// `SmsInboxRepository.scanInbox()` can run its existing filter/parse/dedup
/// pipeline over both sources without caring which one a message came from.
///
/// This is a supplementary source, not the primary one: any failure here
/// (channel not registered, native error, notification access not granted)
/// is swallowed to an empty list rather than surfaced, so it can never turn
/// an otherwise-successful device-SMS scan into a failed one.
class NotificationCaptureAdapter {
  const NotificationCaptureAdapter();

  static const MethodChannel _channel = MethodChannel(
    'finance_app/notification_listener',
  );

  Future<List<RawSmsMessage>> readCaptured() async {
    if (!Platform.isAndroid) return const [];

    List<Object?>? raw;
    try {
      raw = await _channel.invokeMethod<List<Object?>>('getCaptured');
    } catch (_) {
      return const [];
    }
    if (raw == null) return const [];

    return raw
        .whereType<Map<Object?, Object?>>()
        .where(
          (m) =>
              m['title'] is String &&
              m['text'] is String &&
              m['postTime'] is int,
        )
        .map(
          (m) => RawSmsMessage(
            address: m['title']! as String,
            body: m['text']! as String,
            date: DateTime.fromMillisecondsSinceEpoch(m['postTime']! as int),
            source: SmsMessageSource.notification,
          ),
        )
        .toList();
  }
}
