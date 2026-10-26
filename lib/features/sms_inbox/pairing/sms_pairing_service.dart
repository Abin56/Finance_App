import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/sms_background_upload_switch.dart';

/// Why a pairing call was refused or failed. Mirrors the pairing Cloud
/// Functions' stable `details.reason` codes (Flow-Fi-WEB
/// functions/src/sms-pairing/sms-pairing.ts), plus client-side failures.
enum SmsPairingFailure {
  invalid('invalid'),
  expired('expired'),
  used('used'),
  canceled('canceled'),
  superseded('superseded'),
  wrongAccount('wrong_account'),
  syncSuspended('sync_suspended'),
  rateLimited('rate_limited'),
  invalidDevice('invalid_device'),
  notFound('not_found'),
  offline('offline'),
  unauthenticated('unauthenticated'),
  unknown('unknown');

  const SmsPairingFailure(this.code);
  final String code;

  static SmsPairingFailure fromCode(String? code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return unknown;
  }

  /// Plain-language explanation for the pairing screen.
  String get message => switch (this) {
    invalid =>
      "This pairing code isn't valid. Scan the code on FlowFi Web again.",
    expired =>
      'This pairing code expired. Create a new one on FlowFi Web, then scan it.',
    used =>
      'This pairing code was already used. Create a new one on FlowFi Web if you want to pair again.',
    canceled =>
      'This pairing was canceled. Create a new code on FlowFi Web to try again.',
    superseded =>
      'A newer pairing code replaced this one. Scan the code currently shown on FlowFi Web.',
    wrongAccount =>
      'This phone is signed in to a different FlowFi account than the one that created this code. Sign in with the same account you use on the web, then scan again.',
    syncSuspended =>
      'SMS Sync is temporarily paused by FlowFi. Nothing was changed — try again later.',
    rateLimited => 'Too many attempts. Wait a few minutes, then try again.',
    invalidDevice =>
      "This phone couldn't be identified for pairing. Try again.",
    notFound => "This phone isn't paired with your account.",
    offline => "You're offline. Connect to the internet and try again.",
    unauthenticated => 'Sign in to FlowFi first, then scan the code again.',
    unknown => 'Something went wrong. Try again.',
  };

  /// Whether retrying the same code could succeed.
  bool get retryable =>
      this == offline || this == unknown || this == rateLimited;
}

class SmsPairingException implements Exception {
  const SmsPairingException(this.failure);
  final SmsPairingFailure failure;

  @override
  String toString() => 'SmsPairingException(${failure.code})';
}

/// The phone that currently uploads for the account, if any.
class SmsActiveDevice {
  const SmsActiveDevice({
    required this.label,
    required this.isThisDevice,
    this.pairedAt,
  });
  final String label;
  final bool isThisDevice;
  final DateTime? pairedAt;
}

class SmsPairingPreview {
  const SmsPairingPreview({required this.expiresAt, this.activeDevice});
  final DateTime expiresAt;
  final SmsActiveDevice? activeDevice;

  /// Approving would stop a different phone from uploading.
  bool get replacesAnotherPhone =>
      activeDevice != null && !activeDevice!.isThisDevice;
}

class SmsPairingApproval {
  const SmsPairingApproval({
    required this.alreadyPaired,
    this.replacedDeviceLabel,
  });
  final bool alreadyPaired;
  final String? replacedDeviceLabel;
}

/// Invokes one pairing callable and returns its decoded `data`. Throws
/// whatever the transport throws; [SmsPairingService] classifies it.
typedef SmsPairingCallable =
    Future<Object?> Function(String name, Map<String, Object?> data);

Future<Object?> _defaultCallable(String name, Map<String, Object?> data) async {
  final callable = FirebaseFunctions.instance.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
  );
  return (await callable.call<Object?>(data)).data;
}

const MethodChannel _autoSyncChannel = MethodChannel(
  'finance_app/sms_auto_sync',
);

/// "Samsung SM-S918B" — marketing/model strings only, never a hardware id.
Future<String?> readSmsDeviceLabel() => _defaultDeviceLabel();

Future<String?> _defaultDeviceLabel() async {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    return await _autoSyncChannel.invokeMethod<String>('getDeviceLabel');
  } catch (_) {
    return null;
  }
}

/// SharedPreferences key: the uid this install is paired to (set on approval,
/// cleared on disconnect or once the server stops recognizing this device).
/// Only gates whether this phone bothers to send status reports — the server
/// (rules + functions) is what actually authorizes anything.
const String kSmsPairedUidPrefsKey = 'sms_sync_paired_uid';

Future<String?> readSmsPairedUid() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(kSmsPairedUidPrefsKey);
  } catch (_) {
    return null;
  }
}

Future<void> writeSmsPairedUid(String? uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (uid == null) {
      await prefs.remove(kSmsPairedUidPrefsKey);
    } else {
      await prefs.setString(kSmsPairedUidPrefsKey, uid);
    }
  } catch (_) {}
}

/// Client for the SMS Sync pairing Cloud Functions. The token is passed
/// straight through and never logged or stored. Every method throws only
/// [SmsPairingException].
class SmsPairingService {
  SmsPairingService({
    SmsPairingCallable? call,
    Future<String?> Function()? installId,
    Future<String?> Function()? deviceLabel,
    Future<void> Function(String? uid)? savePairedUid,
    this.appVersion,
  }) : _call = call ?? _defaultCallable,
       _installId = installId ?? getOrCreateSmsSyncInstallId,
       _deviceLabel = deviceLabel ?? _defaultDeviceLabel,
       _savePairedUid = savePairedUid ?? writeSmsPairedUid;

  final SmsPairingCallable _call;
  final Future<String?> Function() _installId;
  final Future<String?> Function() _deviceLabel;
  final Future<void> Function(String? uid) _savePairedUid;
  final String? appVersion;

  Future<String> _requireInstallId() async {
    final id = await _installId();
    if (id == null || id.isEmpty) {
      throw const SmsPairingException(SmsPairingFailure.invalidDevice);
    }
    return id;
  }

  Future<Map<Object?, Object?>> _invoke(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final result = await _call(name, data);
      return result is Map ? result : const {};
    } on SmsPairingException {
      rethrow;
    } catch (error) {
      throw SmsPairingException(classifySmsPairingError(error));
    }
  }

  Future<SmsPairingPreview> preview(String token) async {
    final deviceId = await _requireInstallId();
    final data = await _invoke('previewSmsPairingCallable', {
      'token': token,
      'deviceId': deviceId,
    });
    final active = data['activeDevice'];
    return SmsPairingPreview(
      expiresAt: _date(data['expiresAt']) ?? DateTime.now(),
      activeDevice: active is Map
          ? SmsActiveDevice(
              label: active['label'] as String? ?? 'Another phone',
              isThisDevice: active['isThisDevice'] == true,
              pairedAt: _date(active['pairedAt']),
            )
          : null,
    );
  }

  /// The user's explicit approval. [uid] is the signed-in account (recorded
  /// locally so this phone starts sending status reports for it).
  Future<SmsPairingApproval> approve(
    String token, {
    required String uid,
  }) async {
    final deviceId = await _requireInstallId();
    final label = await _deviceLabel();
    final data = await _invoke('approveSmsPairingCallable', {
      'token': token,
      'deviceId': deviceId,
      'deviceLabel': ?label,
      'appVersion': ?appVersion,
    });
    await _savePairedUid(uid);
    return SmsPairingApproval(
      alreadyPaired: data['alreadyPaired'] == true,
      replacedDeviceLabel: data['replacedDeviceLabel'] as String?,
    );
  }

  /// "Not now" — makes the code unusable so it can't be approved later.
  Future<void> cancel(String token) async {
    await _invoke('cancelSmsPairingCallable', {'token': token});
  }

  /// Disconnects THIS phone from the signed-in account (uploads stop).
  Future<void> disconnectThisDevice() async {
    final deviceId = await _requireInstallId();
    try {
      await _invoke('revokeSmsDeviceCallable', {'deviceId': deviceId});
    } on SmsPairingException catch (e) {
      // Already gone server-side: the local flag is just stale.
      if (e.failure != SmsPairingFailure.notFound) rethrow;
    }
    await _savePairedUid(null);
  }

  static DateTime? _date(Object? ms) =>
      ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
}

/// Maps a callable failure to [SmsPairingFailure] using only its code and
/// `details.reason` — never its message.
@visibleForTesting
SmsPairingFailure classifySmsPairingError(Object error) {
  if (error is TimeoutException) return SmsPairingFailure.offline;
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    if (details is Map && details['reason'] is String) {
      return SmsPairingFailure.fromCode(details['reason'] as String);
    }
    switch (error.code) {
      case 'unauthenticated':
        return SmsPairingFailure.unauthenticated;
      case 'unavailable':
      case 'deadline-exceeded':
        return SmsPairingFailure.offline;
    }
  }
  if (error is SocketException) return SmsPairingFailure.offline;
  return SmsPairingFailure.unknown;
}
