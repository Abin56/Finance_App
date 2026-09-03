import 'reminder_signals.dart';

/// [ReminderDetector]'s verdict on one SMS body — a reason is always
/// included on a positive match, same transparency principle every other
/// detector/matcher in this feature follows (see `AccountMatchResult`,
/// `SmsDuplicateReason`).
class ReminderVerdict {
  const ReminderVerdict({required this.isReminder, this.reason});

  const ReminderVerdict.notAReminder() : isReminder = false, reason = null;

  final bool isReminder;
  final String? reason;
}

/// Decides whether a financial-shaped SMS describes an upcoming obligation
/// (a bill/EMI/subscription that has *not* been paid yet) rather than money
/// that has already moved.
///
/// This is deliberately a separate, named component — not folded silently
/// into `FinancialEventExtractor`'s reconciliation — so it can be reasoned
/// about, tested, and improved on its own, per the SMS AI rebuild plan's
/// explicit ask to keep reminders "explicitly separated from actual
/// transactions" rather than only implicitly excluded.
///
/// Deterministic and regex-based today (see `ReminderSignals`); the AI's own
/// `role`/`isLikelyRefundOrReversal`-style read is reconciled against this
/// verdict one layer up, in the extractor's `moneyMovement` reconciliation —
/// this class only ever answers the question using the message text alone,
/// the same posture `SmsFinancialFilter.isFinancial` already takes for "is
/// this financial at all."
class ReminderDetector {
  const ReminderDetector();

  ReminderVerdict detect(String body) {
    if (!ReminderSignals.looksLikeReminder(body))
      return const ReminderVerdict.notAReminder();
    return const ReminderVerdict(
      isReminder: true,
      reason:
          'This message reads as a reminder about an upcoming payment, not a completed transaction.',
    );
  }
}
