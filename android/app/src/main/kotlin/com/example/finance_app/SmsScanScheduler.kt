package com.example.finance_app

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Enqueues the (local-only) background SMS scan. One unique chain, so a burst
 * of messages never spawns concurrent workers; `APPEND_OR_REPLACE` means a
 * message that lands while a scan is running still gets a follow-up scan
 * instead of being dropped. WorkManager persists the queue across process
 * death and reboot. No network constraint: the scan only reads the device
 * provider and writes the local sqflite store.
 */
object SmsScanScheduler {
    const val UNIQUE_NAME = "flowfi_sms_auto_scan"

    // SMS_RECEIVED fires before the provider row is guaranteed to be readable.
    private const val INITIAL_DELAY_SECONDS = 5L
    private const val BACKOFF_SECONDS = 30L

    fun enqueue(context: Context) {
        val request = OneTimeWorkRequestBuilder<SmsScanWorker>()
            .setInitialDelay(INITIAL_DELAY_SECONDS, TimeUnit.SECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork(UNIQUE_NAME)
    }
}
