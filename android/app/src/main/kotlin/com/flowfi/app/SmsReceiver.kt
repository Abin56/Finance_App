package com.flowfi.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import kotlin.concurrent.thread

/**
 * Wakes the background scan when an incoming SMS looks financial. It is a
 * trigger only: the message text is inspected in memory by
 * [SmsFinancialPrefilter] and then discarded — nothing is stored, logged, or
 * uploaded here. The actual read happens later, through the existing
 * `SmsInboxRepository.scanInbox()` against the SMS provider, which also
 * makes a later manual scan of the same message a no-op (same
 * `message_key`).
 *
 * Declared only in the sideload flavor (see src/play/AndroidManifest.xml).
 * Does not require FlowFi to be the default SMS app.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val prefs = AutoSyncPrefs(context)
        if (!prefs.enabled) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val pending = goAsync()
        thread(name = "flowfi-sms-prefilter") {
            try {
                val parts = messages.map {
                    SmsFinancialPrefilter.Part(it.originatingAddress, it.messageBody)
                }
                val whole = SmsFinancialPrefilter.joinParts(parts)
                if (whole.any { SmsFinancialPrefilter.isCandidate(it) }) {
                    prefs.recordSignal()
                    SmsScanScheduler.enqueue(context)
                } else {
                    prefs.recordRejected()
                }
            } finally {
                pending.finish()
            }
        }
    }
}
