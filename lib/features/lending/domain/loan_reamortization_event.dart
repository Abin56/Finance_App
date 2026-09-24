import 'package:cloud_firestore/cloud_firestore.dart';

/// What caused a [LoanReamortizationEvent] — a principal prepayment
/// triggering the automatic solve, or a manual "Edit Loan Terms" action.
/// Additional disbursement is reserved for a future trigger value.
enum ReamortizationTriggerType { prepayment, manualEditTerms }

extension ReamortizationTriggerTypeX on ReamortizationTriggerType {
  static ReamortizationTriggerType fromName(String name) =>
      ReamortizationTriggerType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => ReamortizationTriggerType.manualEditTerms,
      );
}

/// Append-only audit record of one re-amortization — `users/{uid}/loans/{loanId}/reamortizationEvents/{eventId}`.
/// Never edited after creation; a reversal (see
/// `LoanAdvancePaymentRepository`'s payment-deletion path, not yet built)
/// soft-marks it rather than deleting it, keeping the history honest. Gives
/// Loan Detail screens a real "what happened to this loan's principal over
/// time" list instead of reverse-engineering it from diffed installment
/// documents.
class LoanReamortizationEvent {
  LoanReamortizationEvent({
    required this.id,
    required this.loanId,
    required this.triggerType,
    required this.principalBefore,
    required this.principalAfter,
    required this.installmentCountBefore,
    required this.installmentCountAfter,
    required this.date,
    required this.createdAt,
    this.triggeredByPaymentId,
    this.reversed = false,
    this.retiredInstallmentIds = const [],
    this.generatedInstallmentIds = const [],
    this.scheduleTotalAmountBefore,
    this.reversedAt,
    this.reversalId,
  });

  final String id;
  final String loanId;
  final ReamortizationTriggerType triggerType;

  /// FK to the `InstallmentPayment` with `allocationType == principalPrepayment`
  /// that caused this event — null for a manual edit-terms-triggered event.
  final String? triggeredByPaymentId;

  final double principalBefore;
  final double principalAfter;
  final int installmentCountBefore;
  final int installmentCountAfter;
  final DateTime date;
  final DateTime createdAt;

  /// Set when the triggering payment was later deleted and this
  /// re-amortization was undone — kept for audit rather than hard-deleted.
  bool reversed;

  /// The exact ids of the installments this event soft-deleted (the
  /// "untouched" tail that existed before re-amortization) — required to
  /// restore the original schedule on reversal without guessing from
  /// `sequenceNumber`/timestamps. Empty for legacy events predating this
  /// field, which are consequently **not** safely reversible (see
  /// `LoanAdvancePaymentRepository.reversePayment`'s eligibility check).
  final List<String> retiredInstallmentIds;

  /// The exact ids of the installments this event generated (the new tail)
  /// — required to retire them again on reversal. Same legacy caveat as
  /// [retiredInstallmentIds].
  final List<String> generatedInstallmentIds;

  /// `PaymentSchedule.totalAmount` immediately before this event — needed to
  /// restore the schedule's cached total on reversal. Null for legacy
  /// events.
  final double? scheduleTotalAmountBefore;

  /// When [reversed] was set — null until then.
  DateTime? reversedAt;

  /// The idempotency key of the reversal action that set [reversed] — lets a
  /// retried reversal detect it already happened, mirroring
  /// [LoanAdvancePaymentRepository.record]'s own idempotency scheme. Null
  /// until reversed.
  String? reversalId;

  factory LoanReamortizationEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return LoanReamortizationEvent(
      id: snapshot.id,
      loanId: data['loanId'] as String,
      triggerType: ReamortizationTriggerTypeX.fromName(
        data['triggerType'] as String,
      ),
      triggeredByPaymentId: data['triggeredByPaymentId'] as String?,
      principalBefore: (data['principalBefore'] as num).toDouble(),
      principalAfter: (data['principalAfter'] as num).toDouble(),
      installmentCountBefore: (data['installmentCountBefore'] as num).toInt(),
      installmentCountAfter: (data['installmentCountAfter'] as num).toInt(),
      date: (data['date'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      reversed: data['reversed'] as bool? ?? false,
      retiredInstallmentIds:
          (data['retiredInstallmentIds'] as List<dynamic>? ?? [])
              .cast<String>(),
      generatedInstallmentIds:
          (data['generatedInstallmentIds'] as List<dynamic>? ?? [])
              .cast<String>(),
      scheduleTotalAmountBefore:
          (data['scheduleTotalAmountBefore'] as num?)?.toDouble(),
      reversedAt: (data['reversedAt'] as Timestamp?)?.toDate(),
      reversalId: data['reversalId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'loanId': loanId,
      'triggerType': triggerType.name,
      'triggeredByPaymentId': triggeredByPaymentId,
      'principalBefore': principalBefore,
      'principalAfter': principalAfter,
      'installmentCountBefore': installmentCountBefore,
      'installmentCountAfter': installmentCountAfter,
      'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(createdAt),
      'reversed': reversed,
      'retiredInstallmentIds': retiredInstallmentIds,
      'generatedInstallmentIds': generatedInstallmentIds,
      'scheduleTotalAmountBefore': scheduleTotalAmountBefore,
      'reversedAt': reversedAt == null ? null : Timestamp.fromDate(reversedAt!),
      'reversalId': reversalId,
    };
  }
}
