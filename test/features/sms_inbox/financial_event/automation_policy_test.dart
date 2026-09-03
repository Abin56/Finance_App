import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_action.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_policy.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_matcher.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = AutomationPolicy();

  AutomationPolicyInput input({
    ConfidenceLevel confidenceLevel = ConfidenceLevel.high,
    bool accountResolved = true,
    bool amountValid = true,
    bool moneyMovement = true,
    FinancialEventMatchResult matchResult = FinancialEventMatchResult.newEvent,
    bool autoCreateEnabled = false,
  }) {
    return AutomationPolicyInput(
      confidenceLevel: confidenceLevel,
      accountResolved: accountResolved,
      amountValid: amountValid,
      moneyMovement: moneyMovement,
      matchResult: matchResult,
      autoCreateEnabled: autoCreateEnabled,
    );
  }

  test('invalid amount always needs review, regardless of everything else', () {
    expect(
      policy.decide(input(amountValid: false)),
      AutomationAction.needsReview,
    );
  });

  test('possible duplicate always needs review', () {
    expect(
      policy.decide(
        input(matchResult: FinancialEventMatchResult.possibleDuplicate),
      ),
      AutomationAction.needsReview,
    );
  });

  test(
    'refund of an existing event links to it rather than needing review',
    () {
      expect(
        policy.decide(
          input(matchResult: FinancialEventMatchResult.refundOfExisting),
        ),
        AutomationAction.linkToExisting,
      );
    },
  );

  test('reversal of an existing event links to it', () {
    expect(
      policy.decide(
        input(matchResult: FinancialEventMatchResult.reversalOfExisting),
      ),
      AutomationAction.linkToExisting,
    );
  });

  test('additional evidence for an existing event links to it', () {
    expect(
      policy.decide(
        input(matchResult: FinancialEventMatchResult.existingEvent),
      ),
      AutomationAction.linkToExisting,
    );
  });

  test('unresolved account needs review even at high confidence', () {
    expect(
      policy.decide(input(accountResolved: false)),
      AutomationAction.needsReview,
    );
  });

  test('medium confidence needs review even with a resolved account', () {
    expect(
      policy.decide(input(confidenceLevel: ConfidenceLevel.medium)),
      AutomationAction.needsReview,
    );
  });

  test('low confidence needs review', () {
    expect(
      policy.decide(input(confidenceLevel: ConfidenceLevel.low)),
      AutomationAction.needsReview,
    );
  });

  test(
    'high confidence + resolved account + new event, but auto-create disabled, still needs review',
    () {
      expect(
        policy.decide(input(autoCreateEnabled: false)),
        AutomationAction.needsReview,
      );
    },
  );

  test(
    'high confidence + resolved account + new event + auto-create enabled recommends create',
    () {
      expect(
        policy.decide(input(autoCreateEnabled: true)),
        AutomationAction.createTransaction,
      );
    },
  );

  test(
    'no money movement always recommends ignore, even with a valid amount and high confidence',
    () {
      expect(
        policy.decide(input(moneyMovement: false)),
        AutomationAction.ignore,
      );
    },
  );

  test(
    'no money movement recommends ignore even when auto-create is enabled',
    () {
      expect(
        policy.decide(input(moneyMovement: false, autoCreateEnabled: true)),
        AutomationAction.ignore,
      );
    },
  );

  test(
    'a reminder-shaped event (moneyMovement false) is never needsReview just because the amount looks valid',
    () {
      // Guards the exact false-positive the SMS AI rebuild plan calls out:
      // "Your EMI of ₹8,500 is due tomorrow" has a perfectly valid amount but
      // must never be treated the same as a real ₹8,500 debit.
      expect(
        policy.decide(
          input(
            moneyMovement: false,
            amountValid: true,
            confidenceLevel: ConfidenceLevel.high,
          ),
        ),
        AutomationAction.ignore,
      );
    },
  );

  test(
    'resolving a prior reminder/failed event links to it rather than needing review',
    () {
      expect(
        policy.decide(
          input(matchResult: FinancialEventMatchResult.resolvesPriorEvent),
        ),
        AutomationAction.linkToExisting,
      );
    },
  );
}
