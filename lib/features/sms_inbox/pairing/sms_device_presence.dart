import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/firestore_constants.dart';
import '../background/sms_background_upload_switch.dart';
import '../domain/notification_access_availability.dart';
import '../domain/sms_availability.dart';
import 'sms_device_status_reporter.dart';

/// The phone's own sync activity as FlowFi Web shows it. Counts only — no
/// message content, sender, amount or account detail.
enum SmsPresenceSyncPhase { idle, scanning, uploading, done, failed }

class SmsPresenceSync {
  const SmsPresenceSync({
    this.phase = SmsPresenceSyncPhase.idle,
    this.total,
    this.done = 0,
    this.uploaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.updatedAt,
    this.lastSyncAt,
  });

  final SmsPresenceSyncPhase phase;

  /// Known only once the upload targets are counted; `null` while scanning,
  /// so the web never shows a made-up percentage.
  final int? total;
  final int done;
  final int uploaded;
  final int skipped;
  final int failed;
  final DateTime? updatedAt;

  /// Last sync that finished (successfully or with per-item failures).
  final DateTime? lastSyncAt;

  bool get running =>
      phase == SmsPresenceSyncPhase.scanning ||
      phase == SmsPresenceSyncPhase.uploading;

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'total': total,
    'done': done,
    'uploaded': uploaded,
    'skipped': skipped,
    'failed': failed,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
    'lastSyncAt': lastSyncAt?.millisecondsSinceEpoch,
  };

  static SmsPresenceSync fromJson(Object? raw) {
    if (raw is! Map) return const SmsPresenceSync();
    DateTime? date(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    int count(Object? v) => v is int ? v : 0;
    return SmsPresenceSync(
      phase: SmsPresenceSyncPhase.values.firstWhere(
        (p) => p.name == raw['phase'],
        orElse: () => SmsPresenceSyncPhase.idle,
      ),
      total: raw['total'] is int ? raw['total'] as int : null,
      done: count(raw['done']),
      uploaded: count(raw['uploaded']),
      skipped: count(raw['skipped']),
      failed: count(raw['failed']),
      updatedAt: date(raw['updatedAt']),
      lastSyncAt: date(raw['lastSyncAt']),
    );
  }
}

/// Values allowed for `notificationAccess` by firestore.rules.
String notificationAccessReport(NotificationAccessAvailability a) =>
    switch (a) {
      NotificationAccessAvailability.granted => 'granted',
      NotificationAccessAvailability.denied => 'denied',
      NotificationAccessAvailability.notRequestedYet => 'unknown',
      NotificationAccessAvailability.unsupportedPlatform => 'unsupported',
    };

int _bounded(int v) => v.clamp(0, 100000);

/// Builds `users/{uid}/smsDevicePresence/{deviceId}` exactly as firestore.rules
/// requires (every key, nothing else), minus `heartbeatAt`, which the writer
/// sets to the server timestamp.
@visibleForTesting
Map<String, Object?> buildSmsDevicePresencePayload({
  required String deviceId,
  required String? label,
  required String? appVersion,
  required bool foreground,
  required String smsPermission,
  required String notificationAccess,
  required bool autoSyncEnabled,
  required SmsPresenceSync sync,
}) {
  String? trim(String? s, int max) =>
      s == null ? null : (s.length <= max ? s : s.substring(0, max));
  return {
    'deviceId': deviceId,
    'label': trim(label, 60),
    'platform': 'android',
    'appVersion': trim(appVersion, 32),
    'appState': foreground ? 'foreground' : 'background',
    'smsPermission': smsPermission,
    'notificationAccess': notificationAccess,
    'autoSyncEnabled': autoSyncEnabled,
    'syncPhase': sync.phase.name,
    'syncTotal': sync.total == null ? null : _bounded(sync.total!),
    'syncDone': _bounded(sync.done),
    'syncUploaded': _bounded(sync.uploaded),
    'syncSkipped': _bounded(sync.skipped),
    'syncFailed': _bounded(sync.failed),
    'syncUpdatedAt': sync.updatedAt == null
        ? null
        : Timestamp.fromDate(sync.updatedAt!),
    'lastSyncAt': sync.lastSyncAt == null
        ? null
        : Timestamp.fromDate(sync.lastSyncAt!),
  };
}

/// Live heartbeat for FlowFi Web — works before pairing (it authorizes
/// nothing; see firestore.rules `smsDevicePresence`). Each caller passes what
/// it knows (the foreground: verified OS permission, notification access,
/// Auto Sync, app state; the headless worker: sync progress) and the rest
/// comes from values cached in SharedPreferences, which both isolates share.
/// Identical reports within [minInterval] are skipped. Never throws.
class SmsDevicePresenceReporter {
  SmsDevicePresenceReporter({
    FirebaseFirestore Function()? firestore,
    String? Function()? currentUid,
    Future<String?> Function()? installId,
    DateTime Function()? clock,
    this.appVersion,
    this.minInterval = const Duration(seconds: 50),
    this.timeout = const Duration(seconds: 10),
  }) : _firestore = firestore ?? (() => FirebaseFirestore.instance),
       _currentUid = currentUid ?? _defaultUid,
       _installId = installId ?? getOrCreateSmsSyncInstallId,
       _clock = clock ?? DateTime.now;

  final FirebaseFirestore Function() _firestore;
  final String? Function() _currentUid;
  final Future<String?> Function() _installId;
  final DateTime Function() _clock;
  final String? appVersion;
  final Duration minInterval;
  final Duration timeout;

  static const _kForeground = 'sms_presence_foreground';
  static const _kPermission = 'sms_presence_permission';
  static const _kNotification = 'sms_presence_notification';
  static const _kAutoSync = 'sms_presence_auto_sync';
  static const _kLabel = 'sms_presence_label';
  static const _kSync = 'sms_presence_sync';
  static const _kLastSignature = 'sms_presence_last_signature';
  static const _kLastSentMs = 'sms_presence_last_sent_ms';

  static String? _defaultUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// The cached sync activity (shared with the headless worker), for the
  /// phone's own progress UI.
  static Future<SmsPresenceSync> readSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_kSync);
      return raw == null
          ? const SmsPresenceSync()
          : SmsPresenceSync.fromJson(jsonDecode(raw));
    } catch (_) {
      return const SmsPresenceSync();
    }
  }

  /// Returns whether a report was written.
  Future<bool> report({
    bool? foreground,
    SmsAvailability? permission,
    NotificationAccessAvailability? notificationAccess,
    bool? autoSyncEnabled,
    String? label,
    SmsPresenceSync? sync,
    bool force = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      // Cache first, even when signed out, so the next report is complete.
      if (foreground != null) await prefs.setBool(_kForeground, foreground);
      if (permission != null) {
        await prefs.setString(_kPermission, smsPermissionReport(permission));
      }
      if (notificationAccess != null) {
        await prefs.setString(
          _kNotification,
          notificationAccessReport(notificationAccess),
        );
      }
      if (autoSyncEnabled != null) {
        await prefs.setBool(_kAutoSync, autoSyncEnabled);
      }
      if (label != null) await prefs.setString(_kLabel, label);
      if (sync != null) {
        await prefs.setString(_kSync, jsonEncode(sync.toJson()));
      }

      final uid = _currentUid();
      if (uid == null || uid.isEmpty) return false;
      final deviceId = await _installId();
      if (deviceId == null || deviceId.isEmpty) return false;

      final rawSync = prefs.getString(_kSync);
      final payload = buildSmsDevicePresencePayload(
        deviceId: deviceId,
        label: prefs.getString(_kLabel),
        appVersion: appVersion,
        foreground: prefs.getBool(_kForeground) ?? false,
        smsPermission: prefs.getString(_kPermission) ?? 'unknown',
        notificationAccess: prefs.getString(_kNotification) ?? 'unknown',
        autoSyncEnabled: prefs.getBool(_kAutoSync) ?? false,
        sync: rawSync == null
            ? const SmsPresenceSync()
            : SmsPresenceSync.fromJson(jsonDecode(rawSync)),
      );

      final signature =
          '$uid|${jsonEncode(payload, toEncodable: (v) => v is Timestamp ? v.millisecondsSinceEpoch : v.toString())}';
      final lastMs = prefs.getInt(_kLastSentMs);
      final now = _clock();
      if (!force &&
          prefs.getString(_kLastSignature) == signature &&
          lastMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
              minInterval) {
        return false;
      }

      await _firestore()
          .collection(FirestoreCollections.users)
          .doc(uid)
          .collection(FirestoreCollections.smsDevicePresence)
          .doc(deviceId)
          .set({...payload, 'heartbeatAt': FieldValue.serverTimestamp()})
          .timeout(timeout);
      await prefs.setString(_kLastSignature, signature);
      await prefs.setInt(_kLastSentMs, now.millisecondsSinceEpoch);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Throttles sync-progress reports: phase changes always go out, per-item
/// progress at most once per [interval]. The last call is never lost — the
/// caller finishes with a `done`/`failed` phase change.
class SmsPresenceProgressThrottle {
  SmsPresenceProgressThrottle(
    this._reporter, {
    this.interval = const Duration(milliseconds: 1200),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SmsDevicePresenceReporter _reporter;
  final Duration interval;
  final DateTime Function() _clock;
  SmsPresenceSyncPhase? _lastPhase;
  DateTime? _lastSent;
  SmsPresenceSync _last = const SmsPresenceSync();

  Future<void> _chain = Future.value();

  SmsPresenceSync get last => _last;

  /// Writes are serialized, so a slow earlier report can never land after a
  /// later one. Await [flush] before writing a final state yourself.
  Future<void> update(SmsPresenceSync sync) {
    _last = sync;
    final now = _clock();
    final phaseChanged = sync.phase != _lastPhase;
    if (!phaseChanged &&
        _lastSent != null &&
        now.difference(_lastSent!) < interval) {
      return _chain;
    }
    _lastPhase = sync.phase;
    _lastSent = now;
    return _chain = _chain.then(
      (_) => _reporter.report(sync: sync, force: true),
    );
  }

  Future<void> flush() => _chain;
}
