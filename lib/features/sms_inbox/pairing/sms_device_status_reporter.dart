import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/firestore_constants.dart';
import '../background/sms_background_upload_switch.dart';
import '../data/sms_sync_diagnostics_store.dart';
import '../domain/sms_availability.dart';
import '../domain/sms_sync_diagnostics.dart';
import 'sms_pairing_service.dart';

/// Values allowed for `smsPermission` by firestore.rules.
String smsPermissionReport(SmsAvailability availability) =>
    switch (availability) {
      SmsAvailability.granted => 'granted',
      SmsAvailability.denied => 'denied',
      SmsAvailability.permanentlyDenied => 'permanentlyDenied',
      SmsAvailability.unsupportedPlatform => 'unsupported',
      SmsAvailability.notRequestedYet => 'unknown',
    };

/// Builds `users/{uid}/smsDeviceStatus/{deviceId}` exactly as firestore.rules
/// requires (every key, nothing else), minus `reportedAt`, which the writer
/// sets to the server timestamp. Timestamps, counters and fixed codes only —
/// no SMS content, sender, account or card details.
@visibleForTesting
Map<String, Object?> buildSmsDeviceStatusPayload({
  required String deviceId,
  required String smsPermission,
  required bool autoSyncEnabled,
  required SmsSyncDiagnostics diagnostics,
  required int lastUploadedCount,
  String? appVersion,
}) {
  final scanFailed = diagnostics.lastScanError != null;
  final lastScanAt = scanFailed
      ? diagnostics.lastAttemptAt
      : diagnostics.lastScanSuccessAt;
  final lastScanOutcome = lastScanAt == null
      ? null
      : !scanFailed
      ? 'ok'
      : diagnostics.lastScanError == 'permission'
      ? 'permission'
      : 'failed';

  final ok = diagnostics.lastUploadSuccessAt;
  final failed = diagnostics.lastUploadFailureAt;
  final uploadFailedLast = failed != null && (ok == null || failed.isAfter(ok));
  final lastUploadAt = uploadFailedLast ? failed : ok;

  return {
    'deviceId': deviceId,
    'smsPermission': smsPermission,
    'autoSyncEnabled': autoSyncEnabled,
    'cloudSync': diagnostics.cloudState?.name,
    'lastScanAt': lastScanAt == null ? null : Timestamp.fromDate(lastScanAt),
    'lastScanOutcome': lastScanOutcome,
    'lastUploadAt': lastUploadAt == null
        ? null
        : Timestamp.fromDate(lastUploadAt),
    'lastUploadOutcome': lastUploadAt == null
        ? null
        : (uploadFailedLast ? 'failed' : 'ok'),
    'lastUploadedCount': lastUploadedCount.clamp(0, 100000),
    'pendingNotOwnedCount': diagnostics.lastUploadSkippedNotOwned.clamp(
      0,
      100000,
    ),
    'appVersion': appVersion,
  };
}

/// Sends this paired phone's setup/health status so FlowFi Web's setup
/// journey can follow along. Only for an install paired to the signed-in
/// account (local flag set on approval); firestore.rules additionally requires
/// the device to be `active` in smsDevices, and stamps `reportedAt` with the
/// server's time. When the server refuses (revoked/replaced), the local flag
/// is cleared and reporting stops.
///
/// The foreground knows the SMS permission and Auto Sync toggle; the headless
/// worker only knows its scan outcome. Each side passes what it knows and the
/// rest comes from the last values cached here. Identical reports within
/// [minInterval] are skipped. Never throws.
class SmsDeviceStatusReporter {
  SmsDeviceStatusReporter({
    FirebaseFirestore Function()? firestore,
    String? Function()? currentUid,
    Future<String?> Function()? installId,
    Future<String?> Function()? pairedUid,
    Future<void> Function(String? uid)? savePairedUid,
    Future<SmsSyncDiagnostics> Function()? diagnostics,
    DateTime Function()? clock,
    this.appVersion,
    this.minInterval = const Duration(minutes: 2),
    this.timeout = const Duration(seconds: 10),
  }) : _firestore = firestore ?? (() => FirebaseFirestore.instance),
       _currentUid = currentUid ?? _defaultUid,
       _installId = installId ?? getOrCreateSmsSyncInstallId,
       _pairedUid = pairedUid ?? readSmsPairedUid,
       _savePairedUid = savePairedUid ?? writeSmsPairedUid,
       _diagnostics =
           diagnostics ?? (() => const SmsSyncDiagnosticsStore().read()),
       _clock = clock ?? DateTime.now;

  final FirebaseFirestore Function() _firestore;
  final String? Function() _currentUid;
  final Future<String?> Function() _installId;
  final Future<String?> Function() _pairedUid;
  final Future<void> Function(String? uid) _savePairedUid;
  final Future<SmsSyncDiagnostics> Function() _diagnostics;
  final DateTime Function() _clock;
  final String? appVersion;
  final Duration minInterval;
  final Duration timeout;

  static const _kPermission = 'sms_sync_status_permission';
  static const _kAutoSync = 'sms_sync_status_auto_sync';
  static const _kUploaded = 'sms_sync_status_uploaded';
  static const _kLastSignature = 'sms_sync_status_last_signature';
  static const _kLastSentMs = 'sms_sync_status_last_sent_ms';

  static String? _defaultUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Returns whether a report was written.
  Future<bool> report({
    SmsAvailability? permission,
    bool? autoSyncEnabled,
    int? uploadedCount,
    bool force = false,
  }) async {
    try {
      final uid = _currentUid();
      if (uid == null || uid.isEmpty) return false;
      if (await _pairedUid() != uid) return false;
      final deviceId = await _installId();
      if (deviceId == null || deviceId.isEmpty) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (permission != null) {
        await prefs.setString(_kPermission, smsPermissionReport(permission));
      }
      if (autoSyncEnabled != null) {
        await prefs.setBool(_kAutoSync, autoSyncEnabled);
      }
      if (uploadedCount != null) await prefs.setInt(_kUploaded, uploadedCount);

      final payload = buildSmsDeviceStatusPayload(
        deviceId: deviceId,
        smsPermission: prefs.getString(_kPermission) ?? 'unknown',
        autoSyncEnabled: prefs.getBool(_kAutoSync) ?? false,
        diagnostics: await _diagnostics(),
        lastUploadedCount: prefs.getInt(_kUploaded) ?? 0,
        appVersion: appVersion,
      );

      final signature = jsonEncode(
        payload,
        toEncodable: (v) =>
            v is Timestamp ? v.millisecondsSinceEpoch : v.toString(),
      );
      final lastMs = prefs.getInt(_kLastSentMs);
      final now = _clock();
      if (!force &&
          prefs.getString(_kLastSignature) == signature &&
          lastMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
              minInterval) {
        return false;
      }

      try {
        await _firestore()
            .collection(FirestoreCollections.users)
            .doc(uid)
            .collection(FirestoreCollections.smsDeviceStatus)
            .doc(deviceId)
            .set({...payload, 'reportedAt': FieldValue.serverTimestamp()})
            .timeout(timeout);
      } on FirebaseException catch (e) {
        // The server no longer recognizes this phone as an active device for
        // this account (disconnected on the web, or replaced by another phone).
        if (e.code == 'permission-denied') await _savePairedUid(null);
        return false;
      }
      await prefs.setString(_kLastSignature, signature);
      await prefs.setInt(_kLastSentMs, now.millisecondsSinceEpoch);
      return true;
    } catch (_) {
      return false;
    }
  }
}
