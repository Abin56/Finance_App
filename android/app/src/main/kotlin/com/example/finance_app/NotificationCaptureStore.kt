package com.example.finance_app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * Small standalone SQLite store for financial-looking notification captures.
 * Deliberately its own `.db` file rather than the Flutter-managed sqflite
 * database: writing cross-process into a file sqflite owns risks lock or
 * corruption issues between the two engines. Flutter pulls rows from here
 * on-demand (via [MainActivity]'s method channel), the same "read on manual
 * scan" model `SmsReaderAdapter` already uses for the device SMS provider —
 * rows are never pushed into Dart.
 */
class NotificationCaptureStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val DB_NAME = "notification_capture.db"
        private const val DB_VERSION = 1
        private const val TABLE = "captured"

        // Same scale as SmsReaderAdapter's own device-SMS scan cap.
        private const val MAX_ROWS = 500
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                text TEXT NOT NULL,
                post_time INTEGER NOT NULL,
                dedup_hash TEXT NOT NULL UNIQUE
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // No prior schema versions yet.
    }

    /**
     * Insert-or-ignore on (title, text, postTime) — a `MessagingStyle`
     * notification is re-posted (not just updated) on every new message in a
     * thread, so the listener can see the same message more than once.
     * Dart-side idempotency (the `sms_inbox` table's `UNIQUE(message_key)`)
     * would also catch a re-delivered duplicate eventually, but pruning it
     * here keeps this store's own 500-row cap meaningful.
     */
    fun insertIfNew(title: String, text: String, postTime: Long) {
        val dedupHash = "$title|$text|$postTime".hashCode().toString()
        val values = ContentValues().apply {
            put("title", title)
            put("text", text)
            put("post_time", postTime)
            put("dedup_hash", dedupHash)
        }
        writableDatabase.insertWithOnConflict(
            TABLE, null, values, SQLiteDatabase.CONFLICT_IGNORE
        )
        pruneOldest()
    }

    private fun pruneOldest() {
        writableDatabase.execSQL(
            """
            DELETE FROM $TABLE WHERE id NOT IN (
                SELECT id FROM $TABLE ORDER BY post_time DESC LIMIT $MAX_ROWS
            )
            """.trimIndent()
        )
    }

    /** Every captured row, oldest first — mirrors the shape `SmsQuery` hands back. */
    fun getAll(): List<Map<String, Any>> {
        val results = mutableListOf<Map<String, Any>>()
        readableDatabase.query(
            TABLE, arrayOf("title", "text", "post_time"),
            null, null, null, null, "post_time ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                results.add(
                    mapOf(
                        "title" to cursor.getString(0),
                        "text" to cursor.getString(1),
                        "postTime" to cursor.getLong(2)
                    )
                )
            }
        }
        return results
    }
}
