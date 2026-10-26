package com.flowfi.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * Runs the existing Dart scan pipeline (`SmsInboxRepository.scanInbox()`:
 * filter, bank parsers, dedup, local sqflite store) in a headless Flutter
 * engine, so parsing behaviour is identical to a manual scan. Local only —
 * this worker never touches Firestore (cloud upload is intentionally not
 * wired; see docs/sms-auto-sync.md).
 */
class SmsScanWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    private var engine: FlutterEngine? = null

    private data class Outcome(val success: Boolean, val newItems: Int, val error: String?)

    override suspend fun doWork(): Result {
        val prefs = AutoSyncPrefs(applicationContext)
        if (!prefs.enabled) return Result.success()

        val hasSmsAccess = ContextCompat.checkSelfPermission(
            applicationContext, Manifest.permission.READ_SMS
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasSmsAccess) {
            // Revoked permission is not retryable; surface it in the status UI.
            prefs.recordFailure("permission", runAttemptCount)
            return Result.success()
        }

        val signalsAtStart = prefs.pendingSignals
        val outcome = withTimeoutOrNull(SCAN_TIMEOUT_MS) {
            withContext(Dispatchers.Main) { runHeadlessScan() }
        } ?: Outcome(false, 0, "timeout")
        withContext(Dispatchers.Main) {
            engine?.destroy()
            engine = null
        }

        if (outcome.success) {
            // The provider row can land slightly after SMS_RECEIVED; if we were
            // woken by a signal yet found nothing new, try again shortly.
            if (outcome.newItems == 0 && signalsAtStart > 0 && runAttemptCount < PROVIDER_LAG_RETRIES) {
                prefs.recordFailure("not_visible_yet", runAttemptCount + 1)
                return Result.retry()
            }
            prefs.recordSuccess(signalsAtStart)
            return Result.success()
        }

        val code = outcome.error ?: "scan_failed"
        if (code == "permission") {
            prefs.recordFailure(code, runAttemptCount)
            return Result.success()
        }
        prefs.recordFailure(code, runAttemptCount + 1)
        return if (runAttemptCount + 1 >= MAX_ATTEMPTS) Result.failure() else Result.retry()
    }

    private suspend fun runHeadlessScan(): Outcome =
        suspendCancellableCoroutine { continuation ->
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)

            val newEngine = FlutterEngine(applicationContext)
            engine = newEngine
            CaptureChannelHandler.register(newEngine.dartExecutor.binaryMessenger, applicationContext)

            val doneChannel = MethodChannel(newEngine.dartExecutor.binaryMessenger, DONE_CHANNEL)
            doneChannel.setMethodCallHandler { call, result ->
                if (call.method == "done" && continuation.isActive) {
                    val args = call.arguments as? Map<*, *>
                    continuation.resume(
                        Outcome(
                            success = args?.get("success") as? Boolean ?: false,
                            newItems = (args?.get("newItems") as? Number)?.toInt() ?: 0,
                            error = args?.get("error") as? String,
                        )
                    )
                }
                result.success(null)
            }

            newEngine.dartExecutor.executeDartEntrypoint(
                // Resolved in the app's root library (lib/main.dart), which is
                // always compiled in — the library-URI form failed on-device
                // because nothing imported that library.
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "smsBackgroundMain",
                )
            )
        }

    companion object {
        const val DONE_CHANNEL = "finance_app/sms_auto_sync_bg"
        private const val SCAN_TIMEOUT_MS = 2 * 60 * 1000L
        private const val MAX_ATTEMPTS = 6
        private const val PROVIDER_LAG_RETRIES = 2
    }
}
