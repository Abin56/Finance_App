package com.example.finance_app

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationListenerChannel = "finance_app/notification_listener"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

    private fun isNotificationAccessEnabled(): Boolean {
        return NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)
    }

    private fun isBatteryUnrestricted(): Boolean {
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }
}
