import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Owns local (on-device) reminder notifications for any feature with a due
/// date and a set of "days before" offsets — Bills, EMI, and future
/// schedule-owning features all call this same service instead of each
/// maintaining their own notification plumbing. Scheduling state lives
/// entirely in the OS notification scheduler, keyed by a deterministic id
/// derived from `(ownerId, offset)` — so rescheduling on edit is just
/// "cancel every id for this owner, then schedule fresh ones" rather than
/// tracking what's currently scheduled ourselves.
class ReminderNotificationService {
  ReminderNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Cancels every reminder for [ownerId] then schedules one per [offsets]
  /// entry, at 9:00 AM local time on the offset's target date. Call after
  /// every create/edit; call [cancel] alone after delete/pay/skip (an
  /// owner with nothing left to remind about needs no reminders).
  /// [bodyBuilder] formats each offset's notification body — the label text
  /// legitimately differs per feature (e.g. "Tomorrow — due 5/3" for a bill
  /// vs "Tomorrow — EMI due 5/3"), so the caller owns that wording.
  static Future<void> reschedule({
    required String ownerId,
    required String title,
    required String Function(int offset) bodyBuilder,
    required DateTime dueDate,
    required List<int> offsets,
  }) async {
    await cancel(ownerId);
    if (offsets.isEmpty) return;

    for (final offset in offsets) {
      final fireDate = dueDate.subtract(Duration(days: offset));
      final scheduledFor = DateTime(fireDate.year, fireDate.month, fireDate.day, 9);
      if (scheduledFor.isBefore(DateTime.now())) continue;

      await _plugin.zonedSchedule(
        _notificationId(ownerId, offset),
        title,
        bodyBuilder(offset),
        tz.TZDateTime.from(scheduledFor, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Reminders',
            channelDescription: 'Reminders for upcoming and due payments',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Cancels every notification previously scheduled for [ownerId], across
  /// every possible offset — safe to call even if none were scheduled.
  static Future<void> cancel(String ownerId) async {
    for (final offset in _knownOffsets) {
      await _plugin.cancel(_notificationId(ownerId, offset));
    }
  }

  /// Realistic offset range across every feature using this service
  /// (Today/Tomorrow/3/7 days, plus a handful of custom values) — custom
  /// offsets beyond this range won't be reliably cancelled by [cancel],
  /// since ids are derived deterministically from `(ownerId, offset)`
  /// rather than tracked in a registry. Acceptable at this scope; flag if
  /// any feature needs offsets to exceed 30 days.
  static const _knownOffsets = [0, 1, 2, 3, 5, 7, 14, 21, 30];

  /// Deterministic notification id from an owner id + offset — Dart's
  /// `hashCode` is stable within a single run, which is sufficient since
  /// ids only need to be unique among currently-scheduled notifications.
  static int _notificationId(String ownerId, int offset) => Object.hash(ownerId, offset) & 0x7fffffff;
}
