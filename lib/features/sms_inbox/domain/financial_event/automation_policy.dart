import '../sms_confidence_scorer.dart';
import 'automation_action.dart';
import 'transaction_matcher.dart';

/// The inputs [AutomationPolicy.decide] needs — deliberately just the
/// already-computed verdicts from earlier pipeline stages (confidence
/// engine, account matcher, transaction matcher), never re-derives them.
class AutomationPolicyInput {
  const AutomationPolicyInput({
    required this.confidenceLevel,
    required this.accountResolved,
    required this.amountValid,
    required this.moneyMovement,
    required this.matchResult,
    required this.autoCreateEnabled,
  });

  final ConfidenceLevel confidenceLevel;
  final bool accountResolved;

  /// True only when the reconciled amount is non-null and greater than zero.
  final bool amountValid;

  /// `FinancialEvent.moneyMovement.value` — `false` for a reminder, a
  /// failed attempt, or a pending transaction. Checked before every other
  /// input: nothing about confidence or account resolution matters if no
  /// money actually moved.
  final bool moneyMovement;

  final FinancialEventMatchResult matchResult;

  /// User setting, default false. See [AutomationAction]'s doc comment:
  /// even when true, this phase's pipeline never actually executes
  /// [AutomationAction.createTransaction] — the policy's recommendation is
  /// computed and stored for future validation, not acted on.
  final bool autoCreateEnabled;
}

/// A pure decision table — no side effects, no DB access. See
/// [AutomationAction]'s doc comment for why this phase's pipeline only ever
/// *stores* what [decide] returns rather than executing it.
class AutomationPolicy {
  const AutomationPolicy();

  AutomationAction decide(AutomationPolicyInput input) {
    // No real money movement (a reminder, a failed attempt, a pending
    // transaction) → there is nothing to convert. This check comes before
    // amountValid deliberately: a reminder frequently *does* have a valid
    // parsed amount ("₹8,500 is due tomorrow"), and that must never be
    // enough on its own to suggest creating a transaction.
    if (!input.moneyMovement) return AutomationAction.ignore;
    if (!input.amountValid) return AutomationAction.needsReview;

    switch (input.matchResult) {
      case FinancialEventMatchResult.possibleDuplicate:
        return AutomationAction.needsReview;
      case FinancialEventMatchResult.refundOfExisting:
      case FinancialEventMatchResult.reversalOfExisting:
      case FinancialEventMatchResult.resolvesPriorEvent:
        return AutomationAction.linkToExisting;
      case FinancialEventMatchResult.existingEvent:
        return AutomationAction.linkToExisting;
      case FinancialEventMatchResult.updateExisting:
        // Reserved — no scenario produces this match result yet.
        return AutomationAction.needsReview;
      case FinancialEventMatchResult.newEvent:
        break;
    }

    if (!input.accountResolved) return AutomationAction.needsReview;
    if (input.confidenceLevel != ConfidenceLevel.high)
      return AutomationAction.needsReview;

    return input.autoCreateEnabled
        ? AutomationAction.createTransaction
        : AutomationAction.needsReview;
  }
}
