import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';

/// The ground truth a [SmsTestCase] is checked against. Every field is
/// nullable/optional — a test case only asserts what it explicitly cares
/// about; a `null` field is skipped by the evaluation harness rather than
/// compared. This mirrors how a human reviewer would grade the SMS: some
/// dimensions are simply not relevant to a given message (e.g. a promo SMS
/// has no `amount` to check because it should never reach the pipeline).
class ExpectedFinancialClassification {
  const ExpectedFinancialClassification({
    this.shouldPassFilter,
    this.shouldParse,
    this.moneyMovement,
    this.direction,
    this.amount,
    this.eventType,
    this.transactionStatus,
    this.paymentMethod,
    this.merchantEquals,
    this.merchantContains,
    this.merchantIsNull,
    this.isOwnAccountTransfer,
    this.referenceNumberIsNull,
    this.role,
    this.merchantType,
    this.merchantTypeIsNull,
    this.paymentProvider,
    this.paymentProviderIsNull,
    this.categoryNameEquals,
    this.categoryIsNull,
  });

  /// Whether `SmsFinancialFilter.isFinancial` must return this. Set `false`
  /// for promotional/OTP/non-financial noise that must never reach the
  /// parser or the AI at all.
  final bool? shouldPassFilter;

  /// Whether `SmsParserRegistry.tryParse` must produce a non-null result.
  final bool? shouldParse;

  /// The single most safety-critical field: did money actually move?
  final bool? moneyMovement;

  final SmsTransactionDirection? direction;

  /// Compared with a small epsilon tolerance.
  final double? amount;

  final FinancialEventType? eventType;
  final TransactionStatus? transactionStatus;
  final PaymentMethod? paymentMethod;

  /// Exact expected merchant/VPA value.
  final String? merchantEquals;

  /// Substring the resolved merchant must contain (case-insensitive) — use
  /// when the exact resolved string may vary by formatting.
  final String? merchantContains;

  /// Set `true` to assert the merchant must stay unresolved (never invented).
  final bool? merchantIsNull;

  final bool? isOwnAccountTransfer;

  /// Set `true` to assert no reference number should have been extracted.
  final bool? referenceNumberIsNull;

  final FinancialEventRole? role;

  /// Only ever `MerchantType.business` (never `person` — that value is
  /// only ever reachable via AI, see `MerchantIdentityResolver`) or left
  /// null ("don't care") under the regex-only evaluation harness. Use
  /// [merchantTypeIsNull] to positively assert "must stay unresolved".
  final MerchantType? merchantType;

  /// Set `true` to assert the merchant type must stay unresolved (no
  /// catalog match) — never inferred from a bare VPA/explicit-text guess.
  final bool? merchantTypeIsNull;

  final PaymentProvider? paymentProvider;

  /// Set `true` to assert no payment provider signal (explicit phrase or
  /// VPA handle hint) was found — the honest default whenever the message
  /// doesn't name a specific UPI app.
  final bool? paymentProviderIsNull;

  /// The *name* (not id) of the expected category, resolved against
  /// whichever `categories` list the harness run was given — see
  /// `SmsEvaluationHarness`'s category-testing group, which passes a
  /// standard fixture list. Comparing by name rather than a hardcoded id
  /// keeps a corpus case independent of any particular id scheme.
  final String? categoryNameEquals;

  /// Set `true` to assert no category could be resolved at all.
  final bool? categoryIsNull;
}

/// One entry in the SMS evaluation corpus: a raw message plus what FlowFi's
/// pipeline is expected to conclude about it, and why. Built as structured
/// data (rather than assertions buried inside individual `test()` blocks) so
/// the same corpus can be replayed by the evaluation harness, extended by
/// future sessions, and reported on in aggregate rather than only as
/// pass/fail per `test()`.
class SmsTestCase {
  const SmsTestCase({
    required this.id,
    required this.sender,
    required this.body,
    required this.expected,
    required this.explanation,
    this.isDangerousIfMisclassified = false,
    this.knownIssue,
  });

  /// Stable id, e.g. `'reminder-emi-future-tense-01'` — used in reports so a
  /// failure can be traced back to this exact case.
  final String id;

  final String sender;
  final String body;
  final ExpectedFinancialClassification expected;

  /// Why this case exists / what it's guarding against — shown in failure
  /// reports so a human doesn't have to reverse-engineer the intent.
  final String explanation;

  /// Marks a case where a wrong [ExpectedFinancialClassification.moneyMovement]
  /// verdict (in either direction) is not just "a failed test" but a
  /// financially dangerous misclassification — e.g. treating a future-tense
  /// EMI reminder as a completed debit, which could mislead a user into
  /// thinking they've already paid, or suppressing a real debit as a
  /// reminder. The evaluation harness surfaces these separately and more
  /// loudly than an ordinary field mismatch.
  final bool isDangerousIfMisclassified;

  /// Set when this case is a *confirmed, reproduced* gap in the current
  /// pipeline that this session deliberately left unfixed (see the
  /// parallel-development rule against touching production code). The value
  /// is the reason the harness should skip strict grading rather than fail
  /// the suite red forever — remove this once the underlying gap is fixed,
  /// at which point the case should start passing normally.
  final String? knownIssue;
}
