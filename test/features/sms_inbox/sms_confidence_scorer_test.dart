import 'package:finance_app/features/sms_inbox/domain/account_match_result.dart';
import 'package:finance_app/features/sms_inbox/domain/parsed_sms_transaction.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_category.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scorer = SmsConfidenceScorer();

  ParsedSmsTransaction parsed({
    double confidence = 0.85,
    SmsTransactionCategory category = SmsTransactionCategory.creditCardPurchase,
  }) {
    return ParsedSmsTransaction(
      amount: 1250,
      direction: SmsTransactionDirection.debit,
      dateTime: DateTime(2026, 7, 15),
      category: category,
      confidence: confidence,
      rawBody: 'irrelevant',
    );
  }

  const resolvedBankConfirmed = AccountMatchResult(
    isResolved: true,
    matchedAccountId: 'acc-1',
    matchedCardId: 'card-1',
    bankConfirmed: true,
    matchReason: 'Matched HDFC Credit Card ••••1234 by last-4 and bank.',
  );

  const unresolved = AccountMatchResult.unresolved(
    reason: 'No matching account or card found for this message.',
  );

  test(
    'bank-parser confidence + confirmed account + known category = High, no review needed',
    () {
      final result = scorer.score(
        parsed: parsed(),
        accountMatch: resolvedBankConfirmed,
      );

      expect(result.level, ConfidenceLevel.high);
      expect(result.needsReview, isFalse);
      expect(result.reasons, isEmpty);
    },
  );

  test('confirmed account but unknown category = Medium, review needed', () {
    final result = scorer.score(
      parsed: parsed(category: SmsTransactionCategory.unknown),
      accountMatch: resolvedBankConfirmed,
    );

    expect(result.level, ConfidenceLevel.medium);
    expect(result.needsReview, isTrue);
    expect(
      result.reasons,
      contains(
        'Could not confidently determine what kind of transaction this is.',
      ),
    );
  });

  test(
    'unresolved account caps the verdict at Low even with everything else strong',
    () {
      final result = scorer.score(parsed: parsed(), accountMatch: unresolved);

      expect(result.level, ConfidenceLevel.low);
      expect(result.needsReview, isTrue);
      expect(result.reasons, contains(unresolved.matchReason));
    },
  );

  test(
    'a generic-parser, bank-confirmed, categorized message can still be High',
    () {
      // Confidence alone (0.5, the generic-fallback parser's value) is not
      // enough to disqualify a candidate the account/category signals both
      // strongly support.
      final result = scorer.score(
        parsed: parsed(confidence: 0.5),
        accountMatch: resolvedBankConfirmed,
      );

      expect(result.level, ConfidenceLevel.high);
    },
  );

  test(
    'resolved but not bank-confirmed, plus a low-confidence parse, is Low',
    () {
      const resolvedNoBankConfirm = AccountMatchResult(
        isResolved: true,
        matchedAccountId: 'acc-1',
        matchReason: 'Matched HDFC Card ••••1234 by last-4.',
      );

      final result = scorer.score(
        parsed: parsed(
          confidence: 0.5,
          category: SmsTransactionCategory.unknown,
        ),
        accountMatch: resolvedNoBankConfirm,
      );

      expect(result.level, ConfidenceLevel.low);
      expect(result.needsReview, isTrue);
    },
  );

  test(
    'a duplicate always needs review, even at otherwise-High confidence',
    () {
      final result = scorer.score(
        parsed: parsed(),
        accountMatch: resolvedBankConfirmed,
        isDuplicate: true,
      );

      expect(result.needsReview, isTrue);
      expect(
        result.reasons,
        contains('Flagged as a possible duplicate of another message.'),
      );
    },
  );

  test('score is always clamped within 0.0-1.0', () {
    final high = scorer.score(
      parsed: parsed(),
      accountMatch: resolvedBankConfirmed,
    );
    final low = scorer.score(
      parsed: parsed(confidence: 0),
      accountMatch: unresolved,
      isDuplicate: true,
    );

    expect(high.score, inInclusiveRange(0.0, 1.0));
    expect(low.score, inInclusiveRange(0.0, 1.0));
  });
}
