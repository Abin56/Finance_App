import 'sms_message_source.dart';

/// A single SMS (or SMS-shaped notification capture) as read from the
/// device, before any parsing. Kept as a thin, plugin-agnostic value object
/// so `flutter_sms_inbox`'s own message type never leaks past
/// `SmsReaderAdapter` — the rest of this feature (and every unit test) only
/// ever depends on this shape.
class RawSmsMessage {
  const RawSmsMessage({
    required this.address,
    required this.body,
    required this.date,
    this.source = SmsMessageSource.deviceSms,
    this.threadId,
  });

  /// The sender id/number, e.g. `VM-HDFCBK` or `+919812345678` — or, for a
  /// [SmsMessageSource.notification] row, the notification's title (a
  /// display name, since a notification carries no DLT sender id).
  final String address;
  final String body;
  final DateTime date;
  final SmsMessageSource source;
  final int? threadId;
}
