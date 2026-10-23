package com.example.finance_app

/**
 * Coarse, in-memory-only pre-filter shared by [SmsReceiver] and
 * [NotificationCaptureListenerService]. Its only job is to decide whether an
 * incoming message is worth waking the background scan for — it never
 * persists or logs the text it is given. `SmsFinancialFilter.isFinancial`
 * (Dart) remains the authoritative accept/reject call; a false positive here
 * only costs one local scan, so this errs toward rejecting OTP/security
 * content outright and toward accepting ambiguous transaction wording.
 */
object SmsFinancialPrefilter {

    enum class Verdict { ACCEPT, OTP_OR_SECURITY, PROMOTIONAL, REMINDER, NOT_FINANCIAL }

    // Never accepted, regardless of any other wording.
    private val OTP_OR_SECURITY = Regex(
        "\\botp\\b|one[- ]?time password|verification code|passcode|\\bcvv\\b|" +
            "login|log[- ]?in alert|logged in|new device|password|security alert"
    )
    private val PROMOTIONAL = Regex(
        "pre-?approved|apply now|congratulations|click here|limited time|" +
            "t&c apply|\\bdiscount\\b|\\bvoucher\\b|\\bwin\\b|\\bofferz?\\b|upgrade your"
    )
    private val REMINDER = Regex(
        "\\bis due\\b|\\bdue on\\b|\\bdue date\\b|payment due|minimum amount due|" +
            "\\breminder\\b|\\bpay by\\b|\\bpay before\\b"
    )

    // A completed-transaction verb. Lets a genuine alert that merely mentions
    // an offer/due date still through (the Dart filter decides for real).
    private val TRANSACTION_VERB = Regex(
        "\\b(debited|credited|spent|withdrawn|received|paid|deposited)\\b"
    )
    private val CHANNEL_WORD = Regex("\\b(upi|imps|neft|rtgs|emi|transaction)\\b")
    private val AMOUNT = Regex("(rs\\.?|inr|₹)\\s*\\d")

    fun evaluate(text: String): Verdict {
        val lower = text.lowercase()
        if (OTP_OR_SECURITY.containsMatchIn(lower)) return Verdict.OTP_OR_SECURITY

        val hasVerb = TRANSACTION_VERB.containsMatchIn(lower)
        if (!hasVerb && PROMOTIONAL.containsMatchIn(lower)) return Verdict.PROMOTIONAL
        if (!hasVerb && REMINDER.containsMatchIn(lower)) return Verdict.REMINDER

        val hasAmount = AMOUNT.containsMatchIn(lower)
        val looksFinancial = hasAmount && (hasVerb || CHANNEL_WORD.containsMatchIn(lower))
        return if (looksFinancial) Verdict.ACCEPT else Verdict.NOT_FINANCIAL
    }

    fun isCandidate(text: String): Boolean = evaluate(text) == Verdict.ACCEPT

    // Mirrors Dart `NotificationBankEvidence`: notification text can be a
    // personal chat, so it must also look like it came from a bank/UPI system.
    private val BANK_EVIDENCE = listOf(
        Regex("\\b(a/c|acct|account|card)\\b.{0,12}\\d{3,4}"),
        Regex("\\bvpa\\b"),
        Regex("[a-z0-9._-]{2,}@[a-z]{2,}"),
        Regex("\\b(ref(erence)?|utr|rrn)\\b.{0,12}\\d{6,}"),
        Regex("\\b(avl|available)\\.?\\s*bal"),
        Regex("\\bbal(ance)?\\s*[:.]?\\s*(rs|inr|₹)"),
    )

    fun hasBankEvidence(text: String): Boolean {
        val lower = text.lowercase()
        return BANK_EVIDENCE.any { it.containsMatchIn(lower) }
    }

    /** Notification path: the shared verdict plus bank evidence. */
    fun isNotificationCandidate(text: String): Boolean =
        isCandidate(text) && hasBankEvidence(text)

    /** One PDU's worth of an incoming SMS. */
    data class Part(val sender: String?, val body: String?)

    /**
     * Joins a multipart SMS back into whole messages: parts from the same
     * originating address are concatenated in arrival order (the platform
     * already delivers PDUs of one message in segment order). Parts with a
     * null body are skipped; a null sender is grouped under "".
     */
    fun joinParts(parts: List<Part>): List<String> {
        val bySender = LinkedHashMap<String, StringBuilder>()
        for (part in parts) {
            val body = part.body ?: continue
            bySender.getOrPut(part.sender ?: "") { StringBuilder() }.append(body)
        }
        return bySender.values.map { it.toString() }
    }

    /**
     * Package policy for notification capture. Google Messages is matched
     * explicitly instead of relying only on `getDefaultSmsPackage()`, which
     * can be null (no default role holder resolved) or a different app than
     * the one actually posting the RCS notification.
     */
    val MESSAGING_PACKAGES: Set<String> = setOf(
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.mms",
        "com.google.android.apps.messaging.dev",
    )

    fun isMessagingPackage(packageName: String, defaultSmsPackage: String?): Boolean =
        packageName == defaultSmsPackage || packageName in MESSAGING_PACKAGES
}
