import 'financial_event/credit_card_semantics.dart';
import 'financial_event/reminder_signals.dart';
import 'financial_event/transaction_status.dart';
import 'financial_event/transaction_status_signals.dart';
import 'sms_direction_resolver.dart';
import 'sms_event_class.dart';
import 'sms_transaction_date_extractor.dart';
import 'sms_transaction_direction.dart';

/// Bumped whenever the verification rules change in a way already-uploaded
/// candidates should pick up. `SmsCandidateCloudSync` refreshes any cloud
/// document written under an older (or no) version — see there.
const int kSmsCandidateClassificationVersion = 1;

/// The integrity checks one SMS candidate must pass before it may ever
/// affect a balance — computed from the stored raw message, so it is always
/// current for old rows too (no local schema change: see
/// [SmsCandidateVerifier]).
class SmsCandidateVerification {
  const SmsCandidateVerification({
    required this.eventClass,
    required this.transactionStatus,
    required this.direction,
    required this.ownership,
    required this.transactionDate,
    required this.dateSource,
    required this.messageReceivedAt,
    required this.reasons,
    required this.directionMatchesParse,
  });

  final SmsEventClass eventClass;
  final TransactionStatus transactionStatus;
  final DirectionVerdict direction;
  final SmsOwnership ownership;
  final DateTime transactionDate;
  final SmsDateSource dateSource;
  final DateTime messageReceivedAt;

  /// Plain-language reasons this candidate needs a human, beyond the
  /// confidence scorer's own. Empty when every check passed.
  final List<String> reasons;

  /// The verified direction is known AND equals the direction the parser
  /// stored. False means the stored direction is provisional (see
  /// `SmsRegexUtils.extractDirection`) — it must never drive an import.
  final bool directionMatchesParse;

  bool get moneyMovement => eventClass.movesMoney;

  /// Whether this candidate may be sent to FlowFi Web at all. The web cannot
  /// change a candidate's debit/credit, so a candidate whose direction is
  /// not verified stays on the phone (still listed for manual review there,
  /// where the type is chosen during conversion) instead of reaching a
  /// surface that would import it with a guessed sign.
  bool get uploadable => directionMatchesParse;

  /// Every mandatory check passed: money moved, a routine class, direction
  /// proven from context, and ownership proven by an account/card match.
  bool get cleanForImport =>
      reasons.isEmpty &&
      eventClass.isRoutine &&
      direction.isContextual &&
      directionMatchesParse &&
      ownership == SmsOwnership.verified;
}

/// Decides [SmsCandidateVerification] for one parsed SMS. Reuses the
/// existing detectors — [TransactionStatusSignals], [ReminderSignals],
/// [CreditCardSemantics] — that until now fed only the phone-local
/// `FinancialEvent` record, so the uploaded candidate finally agrees with
/// them.
///
/// Classification order (first match wins):
///  1. failed / declined → [SmsEventClass.failedTransaction]
///  2. someone else's account, or a money request → thirdParty/informational
///  3. reversed / refunded → [SmsEventClass.creditCardRefund] (card) or
///     [SmsEventClass.reversal]
///  4. future tense ("will be debited"), or a reminder / due notice with no
///     separate completed-movement sentence → EMI reminder or scheduled
///  5. pending / processing → [SmsEventClass.pendingTransaction]
///  6. balance / limit wording with no movement verb → balance alert
///  7. EMI-conversion notice → informational
///  8. direction not verified → [SmsEventClass.unknown]
///  9. credit-card bill payment / purchase semantics
/// 10. EMI debited
/// 11. no completion evidence at all → unknown; otherwise actual credit/debit
abstract class SmsCandidateVerifier {
  SmsCandidateVerifier._();

  static RegExp _re(String p) => RegExp(p, caseSensitive: false);

  static final RegExp _moneyRequest = _re(
    r'\b(?:has\s+)?requested\s+(?:money|payment|(?:rs|inr|₹))|\bcollect\s+request\b|\bpayment\s+request\b|\brequesting\s+(?:money|payment)\b',
  );
  // "a/c XX1234 of RAMESH KUMAR", "on behalf of" — the account named is not
  // the reader's.
  static final RegExp _otherPersonsAccount = _re(
    r"\b(?:a/c|acct|account)\s*(?:no\.?\s*)?[x*]*\d{3,4}\s+of\s+(?!your\b|you\b)[a-z][a-z.' ]{2,}|\bon\s+behalf\s+of\b",
  );
  static final RegExp _futureTense = _re(
    r'\b(?:will|shall|would)\s+be\s+(?:auto[\s-]?)?(?:debited|deducted|charged|credited|paid|transferred)\b|\bis\s+scheduled\b|\bscheduled\s+(?:for|on)\b',
  );
  static final RegExp _futureCredit = _re(r'\bwill\s+be\s+credited\b');
  static final RegExp _cardDue = _re(
    r'\b(?:total|min(?:imum)?)\.?\s*(?:amount|amt)\.?\s*due\b|\bstatement\b.{0,40}\bgenerated\b|\bpayment\s+due\b|\bdue\s+(?:date|on|by)\b',
  );
  static final RegExp _completedVerb = _re(
    r'\b(?:debited|credited|spent|withdrawn|received|deposited|paid|sent|transferred|deducted)\b',
  );
  static final RegExp _sentenceBreak = RegExp(r'(?<=[.!?])\s+|\n+');
  static final RegExp _emi = _re(r'\bemi\b|\binstal+ments?\b|\bloan\b');
  static final RegExp _emiConversion = _re(
    r'\bconvert(?:ed)?\s+(?:in)?to\s+(?:an?\s+)?emi\b|\bemi\s+conversion\b',
  );
  static final RegExp _balanceWording = _re(
    r'\b(?:avl|available|avail)\.?\s*(?:bal|balance|limit|credit\s+limit)\b|\bbalance\s+(?:is|as\s+on|in)\b|\boutstanding\b|\bcredit\s+limit\b',
  );
  static final RegExp _cardContext = _re(
    r'\bcredit\s+card\b|\bcard\s+(?:ending|no\.?|xx|x{2,}|\*)|\bcard\s+[x*]+\d{3,4}',
  );

  static SmsCandidateVerification verify({
    required String body,
    required DateTime receivedAt,
    required SmsTransactionDirection parsedDirection,
    required bool accountResolved,
    required String? matchedCardId,
  }) {
    final verdict = SmsDirectionResolver.resolve(body);
    final directionMatchesParse =
        verdict.isKnown && verdict.direction == parsedDirection;
    final status = TransactionStatusSignals.detectDetailed(body).status;
    final ownership = accountResolved
        ? SmsOwnership.verified
        : SmsOwnership.unverified;
    final date = SmsTransactionDateExtractor.extract(body, receivedAt);

    final eventClass = _classify(
      body: body,
      verdict: verdict,
      status: status,
      matchedCardId: matchedCardId,
    );

    final reasons = <String>[];
    void add(String reason) {
      if (reason.isNotEmpty && !reasons.contains(reason)) reasons.add(reason);
    }

    add(eventClass.reviewReason);
    if (!verdict.isKnown || !directionMatchesParse) {
      add(
        "Couldn't tell from the message whether money left or entered your account — choose debit or credit yourself.",
      );
    } else if (!verdict.isContextual) {
      add(
        "The message doesn't say whose account moved — confirm the debit/credit before importing.",
      );
    }
    if (eventClass == SmsEventClass.creditCardPurchase &&
        accountResolved &&
        matchedCardId == null) {
      add(
        'Credit card purchase matched to a non-card account — a card purchase is not a bank-account debit. Choose the card.',
      );
    }

    return SmsCandidateVerification(
      eventClass: eventClass,
      transactionStatus: status,
      direction: verdict,
      ownership: ownership,
      transactionDate: date.dateTime,
      dateSource: date.source,
      messageReceivedAt: receivedAt,
      reasons: reasons,
      directionMatchesParse: directionMatchesParse,
    );
  }

  static SmsEventClass _classify({
    required String body,
    required DirectionVerdict verdict,
    required TransactionStatus status,
    required String? matchedCardId,
  }) {
    final cardContext = matchedCardId != null || _cardContext.hasMatch(body);

    if (status == TransactionStatus.failed) {
      return SmsEventClass.failedTransaction;
    }
    // Only when nothing in the message speaks of the reader's own account:
    // "debited from your a/c … credited to a/c XX22 of RAMESH" is the user's
    // own payment, not a third-party event.
    if (!verdict.isContextual && _otherPersonsAccount.hasMatch(body)) {
      return SmsEventClass.thirdPartyEvent;
    }
    if (_moneyRequest.hasMatch(body)) return SmsEventClass.informational;

    if (status == TransactionStatus.reversed ||
        status == TransactionStatus.refunded) {
      return cardContext
          ? SmsEventClass.creditCardRefund
          : SmsEventClass.reversal;
    }

    if (_isScheduled(body)) {
      if (_emi.hasMatch(body)) return SmsEventClass.emiReminder;
      return _futureCredit.hasMatch(body)
          ? SmsEventClass.scheduledCredit
          : SmsEventClass.scheduledDebit;
    }

    // "pending"/"processing" alone; never when the message plainly reports a
    // completed movement ("Rs 500 debited from a/c … processing fee").
    if (status == TransactionStatus.pending && !verdict.isContextual) {
      return SmsEventClass.pendingTransaction;
    }

    if (!_completedVerb.hasMatch(body) && _balanceWording.hasMatch(body)) {
      return SmsEventClass.balanceAlert;
    }
    if (_emiConversion.hasMatch(body)) return SmsEventClass.informational;

    final direction = verdict.direction;
    if (direction == null) return SmsEventClass.unknown;

    switch (CreditCardSemantics.detect(body)) {
      case CreditCardSemanticVerdict.billPayment:
        return SmsEventClass.cardBillPayment;
      case CreditCardSemanticVerdict.purchase:
        return SmsEventClass.creditCardPurchase;
      case CreditCardSemanticVerdict.ambiguous:
      case CreditCardSemanticVerdict.notApplicable:
        break;
    }
    if (matchedCardId != null && direction == SmsTransactionDirection.debit) {
      return SmsEventClass.creditCardPurchase;
    }

    // No completion evidence at all ("Rs 500 at STORE") — not proof money moved.
    // ("spent" counts: TransactionStatusSignals' own completion list lacks it.)
    if (status == TransactionStatus.unknown && !_completedVerb.hasMatch(body)) {
      return SmsEventClass.unknown;
    }

    if (direction == SmsTransactionDirection.debit && _emi.hasMatch(body)) {
      return SmsEventClass.emiDebited;
    }
    return direction == SmsTransactionDirection.credit
        ? SmsEventClass.actualCredit
        : SmsEventClass.actualDebit;
  }

  /// Future tense always means "not yet". A reminder/due notice means "not
  /// yet" unless a SEPARATE sentence reports a completed movement ("Rs 500
  /// spent on card XX12. Total due Rs 5,000 by 15 Nov." is a real purchase).
  static bool _isScheduled(String body) {
    if (_futureTense.hasMatch(body)) return true;
    if (!ReminderSignals.looksLikeReminder(body) && !_cardDue.hasMatch(body)) {
      return false;
    }
    final sentences = body.split(_sentenceBreak);
    final hasCompletedSentence = sentences.any(
      (s) =>
          _completedVerb.hasMatch(s) &&
          !ReminderSignals.looksLikeReminder(s) &&
          !_cardDue.hasMatch(s),
    );
    return !hasCompletedSentence;
  }
}
