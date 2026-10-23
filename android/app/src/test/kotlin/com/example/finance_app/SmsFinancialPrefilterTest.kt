package com.example.finance_app

import com.example.finance_app.SmsFinancialPrefilter.Part
import com.example.finance_app.SmsFinancialPrefilter.Verdict
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsFinancialPrefilterTest {

    @Test fun acceptsSinglePartDebitAlert() {
        val text = "Rs.1,250.00 debited from A/c XX1234 on 20-10-26 to VPA shop@upi. Ref 4123"
        assertEquals(Verdict.ACCEPT, SmsFinancialPrefilter.evaluate(text))
    }

    @Test fun acceptsRcsStyleCreditAlert() {
        val text = "INR 5,000 credited to your account ending 4321 via IMPS"
        assertTrue(SmsFinancialPrefilter.isCandidate(text))
    }

    @Test fun rejectsOtp() {
        assertEquals(
            Verdict.OTP_OR_SECURITY,
            SmsFinancialPrefilter.evaluate("123456 is your OTP for txn of Rs.500 debited. Do not share")
        )
    }

    @Test fun rejectsLoginAndSecurityAlerts() {
        assertEquals(
            Verdict.OTP_OR_SECURITY,
            SmsFinancialPrefilter.evaluate("New device login to your bank app. Rs 0 charged")
        )
    }

    @Test fun rejectsPromotion() {
        assertEquals(
            Verdict.PROMOTIONAL,
            SmsFinancialPrefilter.evaluate("Pre-approved loan of Rs 5,00,000 for you. Apply now")
        )
    }

    @Test fun rejectsReminderWithoutTransactionVerb() {
        assertEquals(
            Verdict.REMINDER,
            SmsFinancialPrefilter.evaluate("Your card bill of Rs 4,200 is due on 25 Oct")
        )
    }

    @Test fun rejectsPersonalChatter() {
        assertEquals(Verdict.NOT_FINANCIAL, SmsFinancialPrefilter.evaluate("see you at 7, bring the money"))
    }

    @Test fun notificationPathRejectsPersonalChatQuotingAmounts() {
        assertFalse(SmsFinancialPrefilter.isNotificationCandidate("I paid Rs 500 for lunch, send it back"))
        assertFalse(SmsFinancialPrefilter.isNotificationCandidate("Hey I sent you Rs.1200 via UPI for the tickets"))
    }

    @Test fun notificationPathAcceptsBankAlertWithEvidence() {
        assertTrue(
            SmsFinancialPrefilter.isNotificationCandidate(
                "Rs. 2,450.00 debited from a/c XX5623 on 20-10-26 to VPA amazon@apl. Ref No 987654321012."
            )
        )
    }

    @Test fun joinsMultipartMessageFromOneSender() {
        val joined = SmsFinancialPrefilter.joinParts(
            listOf(
                Part("VM-HDFCBK", "Rs.900 debited from A/c XX1234 to "),
                Part("VM-HDFCBK", "VPA cafe@upi on 20-10-26."),
            )
        )
        assertEquals(listOf("Rs.900 debited from A/c XX1234 to VPA cafe@upi on 20-10-26."), joined)
        assertTrue(SmsFinancialPrefilter.isCandidate(joined.single()))
    }

    @Test fun multipartSplitMidKeywordOnlyMatchesWhenJoined() {
        val parts = listOf(Part("AX-AXISBK", "Rs.300 deb"), Part("AX-AXISBK", "ited from A/c"))
        assertFalse(parts.any { SmsFinancialPrefilter.isCandidate(it.body!!) })
        assertTrue(SmsFinancialPrefilter.joinParts(parts).any { SmsFinancialPrefilter.isCandidate(it) })
    }

    @Test fun keepsDifferentSendersSeparateAndSkipsNullBodies() {
        val joined = SmsFinancialPrefilter.joinParts(
            listOf(Part("A", "one "), Part("B", "two"), Part("A", "three"), Part("B", null))
        )
        assertEquals(listOf("one three", "two"), joined)
    }

    @Test fun googleMessagesAcceptedEvenWhenDefaultSmsPackageIsNull() {
        assertTrue(SmsFinancialPrefilter.isMessagingPackage("com.google.android.apps.messaging", null))
    }

    @Test fun defaultSmsPackageAcceptedAndUnrelatedAppsRejected() {
        assertTrue(SmsFinancialPrefilter.isMessagingPackage("com.vendor.sms", "com.vendor.sms"))
        assertFalse(SmsFinancialPrefilter.isMessagingPackage("com.whatsapp", "com.vendor.sms"))
        assertFalse(SmsFinancialPrefilter.isMessagingPackage("com.whatsapp", null))
    }

    @Test fun notificationDedupHashIsStableAndSensitive() {
        val a = NotificationCaptureStore.dedupHash("HDFC", "Rs.10 debited", 1L)
        assertEquals(a, NotificationCaptureStore.dedupHash("HDFC", "Rs.10 debited", 1L))
        assertNotEquals(a, NotificationCaptureStore.dedupHash("HDFC", "Rs.10 debited", 2L))
        assertEquals(64, a.length)
    }
}
