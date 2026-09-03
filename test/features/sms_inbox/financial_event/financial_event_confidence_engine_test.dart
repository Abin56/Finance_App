import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_action.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_confidence_engine.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_status.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = FinancialEventConfidenceEngine();

  FinancialEvent event({
    FieldConfidence<double> amount = const FieldConfidence(
      value: 500,
      confidence: 0.9,
      source: EvidenceSource.bothAgree,
    ),
    FieldConfidence<String> accountMatch = const FieldConfidence(
      value: 'acc-1',
      confidence: 1.0,
      source: EvidenceSource.regexOnly,
    ),
    FieldConfidence<String> merchant = const FieldConfidence(
      value: 'Swiggy',
      confidence: 0.9,
      source: EvidenceSource.bothAgree,
    ),
    FieldConfidence<String> category = const FieldConfidence(
      value: 'cat-food',
      confidence: 0.9,
      source: EvidenceSource.regexOnly,
    ),
    FieldConfidence<PaymentMethod> paymentMethod = const FieldConfidence(
      value: PaymentMethod.upi,
      confidence: 0.9,
      source: EvidenceSource.bothAgree,
    ),
  }) {
    return FinancialEvent(
      id: 'evt-1',
      primarySmsItemId: 'sms-1',
      eventType: FinancialEventType.payment,
      role: FinancialEventRole.standalone,
      status: FinancialEventStatus.pendingReview,
      direction: SmsTransactionDirection.debit,
      amount: amount,
      merchant: merchant,
      category: category,
      paymentMethod: paymentMethod,
      accountMatch: accountMatch,
      moneyMovement: const FieldConfidence(
        value: true,
        confidence: 0.9,
        source: EvidenceSource.bothAgree,
      ),
      transactionStatus: const FieldConfidence.unknown(),
      eventDate: DateTime(2026, 7, 15),
      overallConfidence: 0,
      confidenceLevel: ConfidenceLevel.low,
      automationAction: AutomationAction.needsReview,
      needsReview: false,
      reviewReasons: const [],
      createdAt: DateTime(2026, 7, 15),
    );
  }

  test('every field strong and agreeing scores High', () {
    final result = engine.score(event());
    expect(result.level, ConfidenceLevel.high);
  });

  test(
    'unresolved account caps the verdict at Low even with everything else strong',
    () {
      final result = engine.score(
        event(
          accountMatch: const FieldConfidence(
            value: null,
            confidence: 0.0,
            source: EvidenceSource.none,
          ),
        ),
      );
      expect(result.level, ConfidenceLevel.low);
    },
  );

  test(
    'weak merchant/category/paymentMethod but strong amount+account is at least Medium',
    () {
      final result = engine.score(
        event(
          merchant: const FieldConfidence.unknown(),
          category: const FieldConfidence.unknown(),
          paymentMethod: const FieldConfidence.unknown(),
        ),
      );
      // amount(0.30) + account(0.30) alone = 0.60, clears the default medium
      // threshold (0.5) but not high (0.75).
      expect(result.level, ConfidenceLevel.medium);
    },
  );

  test('everything unknown scores Low', () {
    final result = engine.score(
      event(
        amount: const FieldConfidence.unknown(),
        merchant: const FieldConfidence.unknown(),
        category: const FieldConfidence.unknown(),
        paymentMethod: const FieldConfidence.unknown(),
      ),
    );
    expect(result.level, ConfidenceLevel.low);
  });

  test('overall score is always clamped within 0.0-1.0', () {
    final result = engine.score(event());
    expect(result.overall, inInclusiveRange(0.0, 1.0));
  });

  test('custom thresholds are respected', () {
    const strict = FinancialEventConfidenceEngine(
      thresholds: FinancialEventConfidenceThresholds(
        highThreshold: 0.99,
        mediumThreshold: 0.98,
      ),
    );
    final result = strict.score(event());
    expect(
      result.level,
      ConfidenceLevel.low,
      reason: 'nothing clears a 0.99 threshold in this fixture',
    );
  });
}
