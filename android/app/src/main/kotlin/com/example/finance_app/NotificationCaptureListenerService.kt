package com.example.finance_app

import android.app.Notification
import android.os.Build
import android.os.Parcelable
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

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

    override fun onCreate() {
        super.onCreate()
        store = NotificationCaptureStore(applicationContext)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val defaultSmsPackage = Telephony.Sms.getDefaultSmsPackage(applicationContext)
        if (defaultSmsPackage == null || sbn.packageName != defaultSmsPackage) return

        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: return
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

        if (text == null || !looksFinancial(text)) return

        store.insertIfNew(title, text, postTime)
    }

    private fun looksFinancial(text: String): Boolean {
        val lower = text.lowercase()
        if (OTP_PATTERN.containsMatchIn(lower)) return false
        return FINANCIAL_KEYWORDS.any { lower.contains(it) }
    }

    companion object {
        // Coarse pre-filter only — never persist anything OTP-shaped, and
        // only persist what already looks plausibly financial, so this
        // service's data footprint stays as small as the notification stream
        // allows. `SmsFinancialFilter.isFinancial` on the Dart side is the
        // real, authoritative accept/reject call.
        private val OTP_PATTERN = Regex(
            "\\botp\\b|one[- ]?time password|verification code"
        )
        private val FINANCIAL_KEYWORDS = listOf(
            "debited", "credited", "spent", "paid", "withdrawn", "received",
            "deposited", "upi", "imps", "neft", "rtgs", "emi", "transaction"
        )
    }
}
