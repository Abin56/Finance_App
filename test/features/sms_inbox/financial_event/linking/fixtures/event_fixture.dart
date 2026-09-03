import 'package:finance_app/features/sms_inbox/domain/financial_event/automation_action.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/field_confidence.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_role.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_status.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/financial_event_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/merchant_type.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_method.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/payment_provider.dart';
import 'package:finance_app/features/sms_inbox/domain/financial_event/transaction_status.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_confidence_scorer.dart';
import 'package:finance_app/features/sms_inbox/domain/sms_transaction_direction.dart';

FieldConfidence<T> _fc<T>(T? value) => value == null
    ? FieldConfidence<T>.unknown()
    : FieldConfidence<T>(value: value, confidence: 0.9, source: EvidenceSource.regexOnly);

/// Builds a [FinancialEvent] with sensible defaults so a linking test case
/// only has to name the fields it actually cares about — mirrors the
/// terseness `ObligationTestCase`/`SmsTestCase` fixtures already give the
/// Phase 4/Phase 2-3 corpora, adapted here since Phase 5 operates on
/// already-reconciled [FinancialEvent]s rather than raw SMS text.
FinancialEvent buildEvent({
  required String id,
  required DateTime eventDate,
  FinancialEventType eventType = FinancialEventType.payment,
  FinancialEventRole role = FinancialEventRole.standalone,
  FinancialEventStatus status = FinancialEventStatus.pendingReview,
  SmsTransactionDirection direction = SmsTransactionDirection.debit,
  double? amount,
  String? merchant,
  String? category,
  PaymentMethod? paymentMethod,
  String? accountId,
  String? matchedCardId,
  bool? moneyMovement,
  TransactionStatus? transactionStatus,
  String? normalizedSender,
  String? referenceNumber,
  bool isOwnAccountTransfer = false,
  PaymentProvider? paymentProvider,
  MerchantType? merchantType,
  String? primarySmsItemId,
  String? linkedEventId,
  double overallConfidence = 0.8,
  ConfidenceLevel confidenceLevel = ConfidenceLevel.high,
  AutomationAction automationAction = AutomationAction.needsReview,
  bool needsReview = false,
  List<String> reviewReasons = const [],
  DateTime? createdAt,
}) {
  return FinancialEvent(
    id: id,
    primarySmsItemId: primarySmsItemId ?? 'sms-$id',
    eventType: eventType,
    role: role,
    status: status,
    direction: direction,
    amount: _fc(amount),
    merchant: _fc(merchant),
    category: _fc(category),
    paymentMethod: _fc(paymentMethod),
    accountMatch: _fc(accountId),
    moneyMovement: _fc(moneyMovement),
    transactionStatus: _fc(transactionStatus),
    matchedCardId: matchedCardId,
    normalizedSender: normalizedSender,
    eventDate: eventDate,
    overallConfidence: overallConfidence,
    confidenceLevel: confidenceLevel,
    automationAction: automationAction,
    needsReview: needsReview,
    reviewReasons: reviewReasons,
    createdAt: createdAt ?? eventDate,
    referenceNumber: referenceNumber,
    linkedEventId: linkedEventId,
    isOwnAccountTransfer: isOwnAccountTransfer,
    paymentProvider: _fc(paymentProvider),
    merchantType: _fc(merchantType),
  );
}
