/// A single SMS as read from the device inbox, before any parsing. Kept as
/// a thin, plugin-agnostic value object so `flutter_sms_inbox`'s own message
/// type never leaks past `SmsReaderAdapter` — the rest of this feature (and
/// every unit test) only ever depends on this shape.
class RawSmsMessage {
  const RawSmsMessage({required this.address, required this.body, required this.date, this.threadId});

  /// The sender id/number, e.g. `VM-HDFCBK` or `+919812345678`.
  final String address;
  final String body;
  final DateTime date;
  final int? threadId;
}
