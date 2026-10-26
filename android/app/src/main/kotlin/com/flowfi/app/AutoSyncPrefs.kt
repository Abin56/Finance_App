package com.flowfi.app

import android.content.Context
import android.content.SharedPreferences

/**
 * Persistent, content-free state for SMS Auto Sync: an explicit opt-in flag
 * and counters/timestamps for the status UI. No message text, sender, or
 * amount is ever stored here — the durable event data lives in the existing
 * `sms_inbox` sqflite table (and [NotificationCaptureStore] for RCS).
 */
class AutoSyncPrefs(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** Explicit opt-in; defaults to off so nothing is scheduled silently. */
    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    /** Captured signals not yet confirmed scanned by the Dart worker. */
    val pendingSignals: Int get() = prefs.getInt(KEY_PENDING, 0)
    val rejectedCount: Long get() = prefs.getLong(KEY_REJECTED, 0)
    val lastSuccessAt: Long get() = prefs.getLong(KEY_LAST_SUCCESS, 0)
    val lastError: String? get() = prefs.getString(KEY_LAST_ERROR, null)
    val retryCount: Int get() = prefs.getInt(KEY_RETRY, 0)

    @Synchronized
    fun recordSignal() {
        prefs.edit().putInt(KEY_PENDING, pendingSignals + 1).apply()
    }

    @Synchronized
    fun recordRejected() {
        prefs.edit().putLong(KEY_REJECTED, rejectedCount + 1).apply()
    }

    /** Subtracts only the signals that existed when the scan began. */
    @Synchronized
    fun recordSuccess(consumedSignals: Int, nowMillis: Long = System.currentTimeMillis()) {
        prefs.edit()
            .putInt(KEY_PENDING, (pendingSignals - consumedSignals).coerceAtLeast(0))
            .putLong(KEY_LAST_SUCCESS, nowMillis)
            .putInt(KEY_RETRY, 0)
            .remove(KEY_LAST_ERROR)
            .apply()
    }

    /** [code] is a short machine code (e.g. "permission"), never message text. */
    @Synchronized
    fun recordFailure(code: String, attempt: Int) {
        prefs.edit().putString(KEY_LAST_ERROR, code).putInt(KEY_RETRY, attempt).apply()
    }

    @Synchronized
    fun clearSignals() {
        prefs.edit().putInt(KEY_PENDING, 0).apply()
    }

    companion object {
        private const val FILE = "sms_auto_sync"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_PENDING = "pending_signals"
        private const val KEY_REJECTED = "rejected_count"
        private const val KEY_LAST_SUCCESS = "last_success_at"
        private const val KEY_LAST_ERROR = "last_error"
        private const val KEY_RETRY = "retry_count"
    }
}
