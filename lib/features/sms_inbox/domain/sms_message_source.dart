/// Which device API a [RawSmsMessage] was captured through.
///
/// Matters for dedup: [deviceSms] rows share one clock (the SMS content
/// provider's own `date` column), so two of them can be compared with
/// [SmsDedupKey]'s exact-millisecond match. A [notification] row's timestamp
/// comes from the notification shade instead, which is not the same clock —
/// see `SmsInboxDao.findLikelyOriginalByFuzzyMatch` for the looser,
/// time-windowed comparison that exists specifically for this case.
enum SmsMessageSource { deviceSms, notification }

extension SmsMessageSourceX on SmsMessageSource {
  static SmsMessageSource fromName(String? name) {
    return SmsMessageSource.values.firstWhere(
      (source) => source.name == name,
      orElse: () => SmsMessageSource.deviceSms,
    );
  }
}
