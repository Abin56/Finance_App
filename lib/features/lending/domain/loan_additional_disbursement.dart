import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';

/// A single "more principal was added to this loan" event —
/// `users/{uid}/loans/{loanId}/additionalDisbursements/{disbursementId}`.
/// Deliberately NOT an `InstallmentPayment`: a disbursement isn't a payment
/// against any installment (it moves money in the OPPOSITE direction of a
/// payment — see `LoanAdvancePaymentRepository.recordAdditionalDisbursement`'s
/// doc comment) and forcing it into that shape would overload
/// `InstallmentPayment.amount`/`allocationType`/`prepaymentPrincipalAmount`
/// with misleading semantics. Append-only, like `InstallmentPayment` —
/// soft-delete (via [LoanAdvancePaymentRepository.reversePayment]) is the
/// only way its effect changes.
class LoanAdditionalDisbursement extends SoftDeletableEntity {
  LoanAdditionalDisbursement({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.note = '',
    this.transactionId,
    this.reamortizationEventId,
  });

  @override
  final String id;
  final String loanId;

  /// Always positive — the amount of principal added. Never applied toward
  /// any `Installment.amountPaid`; it increases `Loan.loanAmount` directly.
  final double amount;
  final DateTime date;
  final String note;
  final DateTime createdAt;

  /// FK to the `Transaction` this disbursement moved money through.
  final String? transactionId;

  /// FK to the `LoanReamortizationEvent` this disbursement triggered, when
  /// the re-amortization solve succeeded. Null when the solve was
  /// unsolvable or skipped (nothing to re-amortize — the disbursement is
  /// still correctly recorded either way).
  final String? reamortizationEventId;

  factory LoanAdditionalDisbursement.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return LoanAdditionalDisbursement(
        id: snapshot.id,
        loanId: data['loanId'] as String,
        amount: (data['amount'] as num).toDouble(),
        date: (data['date'] as Timestamp).toDate(),
        note: data['note'] as String? ?? '',
        createdAt: (data['createdAt'] as Timestamp).toDate(),
        transactionId: data['transactionId'] as String?,
        reamortizationEventId: data['reamortizationEventId'] as String?,
      )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'loanId': loanId,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'transactionId': transactionId,
      'reamortizationEventId': reamortizationEventId,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null
          ? null
          : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
