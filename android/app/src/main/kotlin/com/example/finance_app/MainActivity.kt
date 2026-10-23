package com.example.finance_app

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.ContextCompat
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationListenerChannel = "finance_app/notification_listener"
    private val AUTO_SYNC_CHANNEL = "finance_app/sms_auto_sync"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerAutoSyncChannel(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationListenerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isNotificationAccessEnabled())
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "getCaptured" -> result.success(
                        NotificationCaptureStore(applicationContext).getAll()
                    )
                    "isBatteryUnrestricted" -> result.success(isBatteryUnrestricted())
                    "requestBatteryUnrestricted" -> {
                        // Goes straight to the system's one-tap "Allow" dialog for this
                        // app rather than a generic settings list — the OEM-specific
                        // per-app Battery page (e.g. Samsung's Unrestricted/Optimised/
                        // Restricted picker) is just that OEM's UI on top of this same
                        // underlying Doze-whitelist mechanism, so this reaches the
                        // correct control regardless of manufacturer.
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * SMS Auto Sync settings/status. Status carries counters and timestamps
     * only — never message content. Enabling schedules nothing by itself;
     * work is enqueued only when a financial-looking message arrives (or via
     * `scanNow`).
     */
    private fun registerAutoSyncChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTO_SYNC_CHANNEL)
            .setMethodCallHandler { call, result ->
                val prefs = AutoSyncPrefs(applicationContext)
                when (call.method) {
                    "getStatus" -> result.success(
                        mapOf(
                            "supported" to isSmsReceiverPresent(),
                            "enabled" to prefs.enabled,
                            "receiveSmsGranted" to hasPermission(Manifest.permission.RECEIVE_SMS),
                            "readSmsGranted" to hasPermission(Manifest.permission.READ_SMS),
                            "pendingSignals" to prefs.pendingSignals,
                            "rejectedCount" to prefs.rejectedCount,
                            "lastSuccessAt" to prefs.lastSuccessAt,
                            "lastError" to prefs.lastError,
                            "retryCount" to prefs.retryCount,
                        )
                    )
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        prefs.enabled = enabled
                        if (!enabled) {
                            SmsScanScheduler.cancel(applicationContext)
                            prefs.clearSignals()
                        }
                        result.success(null)
                    }
                    "scanNow" -> {
                        if (prefs.enabled) SmsScanScheduler.enqueue(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** False in the `play` flavor, whose manifest removes [SmsReceiver]. */
    private fun isSmsReceiverPresent(): Boolean = try {
        packageManager.getReceiverInfo(ComponentName(this, SmsReceiver::class.java), 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun isNotificationAccessEnabled(): Boolean {
        return NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)
    }

    private fun isBatteryUnrestricted(): Boolean {
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }
}
