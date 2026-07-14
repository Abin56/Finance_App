import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/audit_entry.dart';
import '../../models/soft_deletable_entity.dart';
import 'owner_type.dart';
import 'schedule_type.dart';

/// A repayment plan for one feature entity (a [OwnerType.loan], future EMI,
/// split expense, or bill) — the total amount owed, how it repeats, and how
/// many installments to generate. The schedule itself never mutates on
/// payment; only its child [Installment] documents do (see
/// `InstallmentRepository`), unlike the older single-rolling-document `Bill`
/// model this replaces for new features.
class PaymentSchedule extends SoftDeletableEntity {
  PaymentSchedule({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.totalAmount,
    required this.scheduleType,
    required this.firstDueDate,
    required this.createdAt,
    this.customIntervalDays,
    this.installmentCount,
    this.notes = '',
  });

  @override
  final String id;
  final OwnerType ownerType;
  final String ownerId;
  double totalAmount;
  ScheduleType scheduleType;

  /// The first (or only) installment's due date — not the owning entity's
  /// origination/disbursement date, which the owner (e.g. `Loan.loanDate`)
  /// tracks separately.
  DateTime firstDueDate;

  /// Only meaningful when [scheduleType] is [ScheduleType.custom].
  int? customIntervalDays;

  /// Number of installments to generate. Null means open-ended/rolling —
  /// not used by Lending; reserved for a future recurring-schedule owner.
  /// Mutable so `PaymentScheduleRepository.editSchedule` can update it after
  /// `EmiRepository.editEmiTerms` regenerates the unpaid tail with a
  /// different installment count.
  int? installmentCount;

  String notes;
  final DateTime createdAt;

  bool get isFixedCount => installmentCount != null;

  factory PaymentSchedule.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return PaymentSchedule(
      id: snapshot.id,
      ownerType: OwnerTypeX.fromName(data['ownerType'] as String),
      ownerId: data['ownerId'] as String,
      totalAmount: (data['totalAmount'] as num).toDouble(),
      scheduleType: ScheduleTypeX.fromName(data['scheduleType'] as String),
      firstDueDate: (data['firstDueDate'] as Timestamp).toDate(),
      customIntervalDays: (data['customIntervalDays'] as num?)?.toInt(),
      installmentCount: (data['installmentCount'] as num?)?.toInt(),
      notes: data['notes'] as String? ?? '',
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
      'ownerType': ownerType.name,
      'ownerId': ownerId,
      'totalAmount': totalAmount,
      'scheduleType': scheduleType.name,
      'firstDueDate': Timestamp.fromDate(firstDueDate),
      'customIntervalDays': customIntervalDays,
      'installmentCount': installmentCount,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
