import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import '../../../core/payment_schedule/domain/installment.dart';
import '../../../core/payment_schedule/domain/installment_status.dart';
import '../../../core/payment_schedule/domain/schedule_type.dart';
import 'loan_interest.dart';
import 'loan_repayment_type.dart';
import 'loan_status.dart';

/// Money lent to a [Person], tracked through a linked `PaymentSchedule`
/// (see [scheduleId]) rather than a cached balance — `Installment` already
/// owns the cached amountPaid roll-up, so `Loan` doesn't need a second
/// cache. Supports both a single due-date repayment and installment (EMI)
/// repayment, with optional flat or reducing-balance interest.
class Loan extends SoftDeletableEntity {
  Loan({
    required this.id,
    required this.personId,
    required this.loanAmount,
    required this.loanDate,
    required this.repaymentType,
    required this.scheduleId,
    required this.createdAt,
    this.name,
    this.interest,
    this.dueDate,
    this.installmentFrequency,
    this.installmentCount,
    this.notes = '',
    this.isClosed = false,
  });

  @override
  final String id;
  final String personId;
  String? name;

  /// Locked once any payment has been recorded — see `LoanRepository.editLoan`.
  double loanAmount;

  /// Immutable after creation — drives the one-shot schedule/installment
  /// generation in `LoanRepository.createLoan`, with no "regenerate" path.
  final LoanInterest? interest;

  final DateTime loanDate;

  /// Immutable after creation.
  final LoanRepaymentType repaymentType;

  /// Required when [repaymentType] is [LoanRepaymentType.oneTime]; null for
  /// installment loans (their installments carry their own due dates).
  final DateTime? dueDate;

  /// Required when [repaymentType] is [LoanRepaymentType.installment]; null
  /// for one-time loans.
  final ScheduleType? installmentFrequency;

  /// Required when [repaymentType] is [LoanRepaymentType.installment]; null
  /// (not 1) for one-time loans, so this field stays a faithful record of
  /// what the user actually chose.
  final int? installmentCount;

  String notes;

  /// The `PaymentSchedule.id` this loan's receivable is tracked through.
  final String scheduleId;

  /// Explicit user action ("Close Loan") — not derived, since "fully paid"
  /// and "closed" are different concepts (a loan can be closed early as
  /// forgiven/written-off even if not fully repaid).
  bool isClosed;

  final DateTime createdAt;

  /// This loan's current standing. Requires the caller to supply the
  /// linked schedule's installments (unlike `Bill.status`/`Person.isCreditor`'s
  /// zero-arg getters) since a Loan's payment state lives on separate
  /// `Installment` documents, not on the Loan itself.
  LoanStatus statusGiven(List<Installment> installments) {
    if (isClosed) return LoanStatus.closed;
    final hasOverdue = installments.any((i) => i.status == InstallmentStatus.overdue);
    return hasOverdue ? LoanStatus.overdue : LoanStatus.active;
  }

  factory Loan.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Loan(
      id: snapshot.id,
      personId: data['personId'] as String,
      name: data['name'] as String?,
      loanAmount: (data['loanAmount'] as num).toDouble(),
      interest: data['interest'] == null ? null : LoanInterest.fromMap(data['interest'] as Map<String, dynamic>),
      loanDate: (data['loanDate'] as Timestamp).toDate(),
      repaymentType: LoanRepaymentTypeX.fromName(data['repaymentType'] as String),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      installmentFrequency: data['installmentFrequency'] == null
          ? null
          : ScheduleTypeX.fromName(data['installmentFrequency'] as String),
      installmentCount: (data['installmentCount'] as num?)?.toInt(),
      notes: data['notes'] as String? ?? '',
      scheduleId: data['scheduleId'] as String,
      isClosed: data['isClosed'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'personId': personId,
      'name': name,
      'loanAmount': loanAmount,
      'interest': interest?.toMap(),
      'loanDate': Timestamp.fromDate(loanDate),
      'repaymentType': repaymentType.name,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
      'installmentFrequency': installmentFrequency?.name,
      'installmentCount': installmentCount,
      'notes': notes,
      'scheduleId': scheduleId,
      'isClosed': isClosed,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
