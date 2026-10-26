package com.flowfi.app

import android.app.Notification
import android.os.Build
import android.os.Parcelable
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Captures bank/transaction notification text so it can be scanned alongside
 * the device SMS inbox — the only way to observe RCS message content
 * client-side, since RCS (unlike SMS/MMS) is never exposed through
 * `content://sms` or any other public content provider. See
 * `docs/sms-inbox-feature.md` for why this exists.
 *
 * Privacy boundary: [onNotificationPosted] fires for every notification on
 * the device while this service is enabled. Everything not from the current
 * default SMS/RCS app is rejected immediately, before its content is read at
 * all, and only notifications that already look financial are ever written
 * to [NotificationCaptureStore] — the real accept/reject call still happens
 * on the Dart side via `SmsFinancialFilter.isFinancial`.
 */
class NotificationCaptureListenerService : NotificationListenerService() {

    private lateinit var store: NotificationCaptureStore

    // Release builds stay silent: messaging package names are only logged
    // when someone enables the tag with `adb shell setprop log.tag.$TAG DEBUG`.
    private inline fun debugLog(message: () -> String) {
        if (Log.isLoggable(TAG, Log.DEBUG)) Log.d(TAG, message())
    }

    private companion object {
        const val TAG = "FinanceAppNotifCap"
    }

    override fun onCreate() {
        super.onCreate()
        store = NotificationCaptureStore(applicationContext)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Package check happens before any notification content is read.
        // `getDefaultSmsPackage()` may be null or a different app than the one
        // posting RCS alerts, so Google Messages & friends are matched by an
        // explicit allowlist too (see SmsFinancialPrefilter.MESSAGING_PACKAGES).
        // Diagnostics log package names and lengths only — never content.
        val defaultSmsPackage = Telephony.Sms.getDefaultSmsPackage(applicationContext)
        if (!SmsFinancialPrefilter.isMessagingPackage(sbn.packageName, defaultSmsPackage)) {
            return
        }
        debugLog {
            "messaging pkg=${sbn.packageName} defaultSmsPkg=$defaultSmsPackage"
        }

        val extras = sbn.notification.extras
        // A MessagingStyle post can omit EXTRA_TITLE; the title is only a
        // display label, so don't drop an otherwise valid alert over it.
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
            ?: "Messages"
        var text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        var postTime = sbn.postTime

        // Google Messages posts one grouped MessagingStyle notification per
        // conversation and re-posts it (not just updates it) on every new
        // message — EXTRA_TEXT alone can be a stale summary, so prefer the
        // newest individual message when present.
        val messagesBundleArray = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            extras.getParcelableArray(Notification.EXTRA_MESSAGES, Parcelable::class.java)
        } else {
            @Suppress("DEPRECATION")
            extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        }
        val latestMessage = if (messagesBundleArray != null &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
        ) {
            // The platform's own MessagingStyle.Message — not
            // androidx.core's, whose getMessagesFromBundleArray is
            // package-private and inaccessible from app code.
            Notification.MessagingStyle.Message
                .getMessagesFromBundleArray(messagesBundleArray)
                .maxByOrNull { it.timestamp }
        } else {
            null
        }
        if (latestMessage != null) {
            text = latestMessage.text?.toString() ?: text
            postTime = latestMessage.timestamp
        }

        debugLog {
            "package filter passed; hasMessagingStyleMessages=${messagesBundleArray != null} " +
                "textLen=${text?.length ?: -1}"
        }

        if (text == null) {
            debugLog { "rejected: no text extracted" }
            return
        }
        // Coarse pre-filter only — never persist anything OTP/security-shaped,
        // and only persist what already looks plausibly financial, so this
        // service's data footprint stays as small as the notification stream
        // allows. `SmsFinancialFilter.isFinancial` on the Dart side is the
        // real, authoritative accept/reject call.
        val verdict = SmsFinancialPrefilter.evaluate(text)
        if (verdict != SmsFinancialPrefilter.Verdict.ACCEPT) {
            debugLog { "rejected: $verdict" }
            return
        }
        // Personal RCS chats can quote amounts too; require bank/UPI evidence.
        if (!SmsFinancialPrefilter.hasBankEvidence(text)) {
            debugLog { "rejected: no bank evidence" }
            return
        }

        // Re-posts/updates of the same MessagingStyle thread hit the store's
        // UNIQUE dedup hash and report `false` — no second scan is scheduled.
        val isNew = store.insertIfNew(title, text, postTime)
        val prefs = AutoSyncPrefs(applicationContext)
        if (isNew && prefs.enabled) {
            prefs.recordSignal()
            SmsScanScheduler.enqueue(applicationContext)
        }
    }
}
