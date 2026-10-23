/// Snapshot of the native SMS Auto Sync state (see `AutoSyncPrefs.kt`).
/// Counters and timestamps only — no message content.
class SmsAutoSyncStatus {
  const SmsAutoSyncStatus({
    required this.supported,
    required this.enabled,
    required this.receiveSmsGranted,
    required this.readSmsGranted,
    required this.pendingSignals,
    required this.rejectedCount,
    required this.retryCount,
    this.lastSuccessAt,
    this.lastError,
  });

  const SmsAutoSyncStatus.unsupported()
    : supported = false,
      enabled = false,
      receiveSmsGranted = false,
      readSmsGranted = false,
      pendingSignals = 0,
      rejectedCount = 0,
      retryCount = 0,
      lastSuccessAt = null,
      lastError = null;

  factory SmsAutoSyncStatus.fromMap(Map<Object?, Object?> map) {
    final lastSuccess = (map['lastSuccessAt'] as num?)?.toInt() ?? 0;
    return SmsAutoSyncStatus(
      supported: map['supported'] as bool? ?? false,
      enabled: map['enabled'] as bool? ?? false,
      receiveSmsGranted: map['receiveSmsGranted'] as bool? ?? false,
      readSmsGranted: map['readSmsGranted'] as bool? ?? false,
      pendingSignals: (map['pendingSignals'] as num?)?.toInt() ?? 0,
      rejectedCount: (map['rejectedCount'] as num?)?.toInt() ?? 0,
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastSuccessAt: lastSuccess > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastSuccess)
          : null,
      lastError: map['lastError'] as String?,
    );
  }

  final bool supported;
  final bool enabled;
  final bool receiveSmsGranted;
  final bool readSmsGranted;
  final int pendingSignals;
  final int rejectedCount;
  final int retryCount;
  final DateTime? lastSuccessAt;
  final String? lastError;

  /// Auto Sync can only actually capture when it is on *and* the OS still
  /// grants both SMS permissions — a revoked permission silently disables it.
  bool get isEffective => enabled && receiveSmsGranted && readSmsGranted;

  bool get permissionsRevoked =>
      enabled && (!receiveSmsGranted || !readSmsGranted);

  /// Plain-language error for the status UI, or null when healthy.
  String? get errorLabel => switch (lastError) {
    null => null,
    'permission' => 'SMS permission was removed. Re-grant it to resume.',
    'not_visible_yet' => 'Waiting for the message to appear — retrying.',
    'timeout' => 'The background scan timed out — retrying.',
    _ => 'The last background scan failed — retrying.',
  };
}
