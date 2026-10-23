package com.example.finance_app

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The read-only half of the `finance_app/notification_listener` channel, so a
 * headless engine (see [SmsScanWorker]) can read captured RCS notifications
 * exactly as the foreground app does. Activity-bound methods
 * (`openSettings`, battery prompts) stay in [MainActivity].
 */
object CaptureChannelHandler {
    const val CHANNEL = "finance_app/notification_listener"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(
                    NotificationManagerCompat.getEnabledListenerPackages(context)
                        .contains(context.packageName)
                )
                "getCaptured" -> result.success(NotificationCaptureStore(context).getAll())
                else -> result.notImplemented()
            }
        }
    }
}
