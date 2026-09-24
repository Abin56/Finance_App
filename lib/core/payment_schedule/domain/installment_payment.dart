import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/audit_entry.dart';
import '../../models/soft_deletable_entity.dart';
import 'owner_type.dart';
import 'payment_allocation_type.dart';

/// A single payment applied toward an [Installment]. Append-only like
/// `LedgerEntry`/`PaymentRecord` — soft-delete (which reverses its effect on
/// [Installment.amountPaid]) and restore are the only ways its effect
/// changes.
class InstallmentPayment extends SoftDeletableEntity {
  InstallmentPayment({
    required this.id,
    required this.installmentId,
    required this.scheduleId,
    required this.ownerType,
    required this.ownerId,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.note = '',
    this.settlementMethod,
    this.billingCycleLabel,
    this.remainingBalanceAfterPayment,
    this.payerPersonId,
    this.allocationType = PaymentAllocationType.regularEmi,
    this.prepaymentPrincipalAmount,
    this.prepaymentPolicyApplied,
    this.reamortizationEventId,
    this.transactionId,
  });

  @override
  final String id;
  final String installmentId;

  /// Denormalized so a schedule-wide "full payment history" query doesn't
  /// need to fan out per-installment.
  final String scheduleId;
  final OwnerType ownerType;
  final String ownerId;

  /// Always positive — payments only ever add toward [Installment.amountPaid].
  final double amount;
  final DateTime date;
  final String note;
  final DateTime createdAt;

  /// How this payment was made (e.g. "Cash", "UPI", "Bank Transfer") —
  /// nullable free-text, only meaningfully populated for split-expense
  /// settlements today; other owner types never set it.
  final String? settlementMethod;

  /// Display label (e.g. "Jul 2026") for the billing cycle this payment was
  /// recorded in, per `CycleAnchor` — nullable, computed at write time by
  /// the caller.
  final String? billingCycleLabel;

  /// This installment's `remainingAmount` immediately after this payment was
  /// applied — nullable, filled at write time from the installment already
  /// in hand.
  final double? remainingBalanceAfterPayment;

  /// The [Person] who actually handed over the money for this payment, when
  /// that's someone other than the account owner — mirrors `PayerSource`
  /// (see `RecordLoanPaymentSheet._resolvePayer`). `null` means the account
  /// owner ("You") paid it themselves; callers that don't collect a payer at
  /// all (e.g. Bills, split-expense settlements) also leave this null.
  final String? payerPersonId;

  /// Why this payment was recorded — see [PaymentAllocationType]. Absent on
  /// every document written before this field existed, safely defaulting to
  /// [PaymentAllocationType.regularEmi] on read (see
  /// [PaymentAllocationTypeX.fromName]): an old payment is definitionally an
  /// ordinary one, since prepayment/advance classification didn't exist yet.
  final PaymentAllocationType allocationType;

  /// The portion of [amount] that was NOT applied toward any installment's
  /// `amountDue` — only set when [allocationType] is
  /// [PaymentAllocationType.principalPrepayment]. Null/zero for every other
  /// type. See `LoanAdvancePaymentRepository`'s doc comment for how this
  /// overflow is recorded (a ledger-only sibling payment doc attached to the
  /// schedule's last installment, never applied via `applyPayment`).
  final double? prepaymentPrincipalAmount;

  /// Which re-amortization policy actually ran as a result of this payment
  /// — only set alongside [prepaymentPrincipalAmount] when a re-amortization
  /// was solved and applied (see [PrepaymentReamortizationSolved]). Null
  /// when the prepayment was recorded but re-amortization was skipped
  /// (unsolvable, or nothing left to re-amortize) or for non-prepayment
  /// payments.
  final String? prepaymentPolicyApplied;

  /// FK to the `LoanReamortizationEvent`/`EmiReamortizationEvent` this
  /// payment triggered, when one was written. Null otherwise.
  final String? reamortizationEventId;

  /// FK to the `Transaction` this payment moved money through — 1:1 for the
  /// first payment doc of a given user action; sibling fan-out docs from the
  /// same lump-sum/prepayment action point at the same id (one bank
  /// movement, possibly several installments settled). Null only for
  /// payments recorded before Account/Transaction integration existed for
  /// this write path.
  final String? transactionId;

  factory InstallmentPayment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return InstallmentPayment(
        id: snapshot.id,
        installmentId: data['installmentId'] as String,
        scheduleId: data['scheduleId'] as String,
        ownerType: OwnerTypeX.fromName(data['ownerType'] as String),
        ownerId: data['ownerId'] as String,
        amount: (data['amount'] as num).toDouble(),
        date: (data['date'] as Timestamp).toDate(),
        note: data['note'] as String? ?? '',
        createdAt: (data['createdAt'] as Timestamp).toDate(),
        settlementMethod: data['settlementMethod'] as String?,
        billingCycleLabel: data['billingCycleLabel'] as String?,
        remainingBalanceAfterPayment:
            (data['remainingBalanceAfterPayment'] as num?)?.toDouble(),
        payerPersonId: data['payerPersonId'] as String?,
        allocationType: PaymentAllocationTypeX.fromName(
          data['allocationType'] as String?,
        ),
        prepaymentPrincipalAmount:
            (data['prepaymentPrincipalAmount'] as num?)?.toDouble(),
        prepaymentPolicyApplied: data['prepaymentPolicyApplied'] as String?,
        reamortizationEventId: data['reamortizationEventId'] as String?,
        transactionId: data['transactionId'] as String?,
      )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'installmentId': installmentId,
      'scheduleId': scheduleId,
      'ownerType': ownerType.name,
      'ownerId': ownerId,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'settlementMethod': settlementMethod,
      'billingCycleLabel': billingCycleLabel,
      'remainingBalanceAfterPayment': remainingBalanceAfterPayment,
      'payerPersonId': payerPersonId,
      'allocationType': allocationType.name,
      'prepaymentPrincipalAmount': prepaymentPrincipalAmount,
      'prepaymentPolicyApplied': prepaymentPolicyApplied,
      'reamortizationEventId': reamortizationEventId,
      'transactionId': transactionId,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null
          ? null
          : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
