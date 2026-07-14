import 'package:cloud_firestore/cloud_firestore.dart';

import '../../extensions/date_extensions.dart';
import '../../models/audit_entry.dart';
import '../../models/soft_deletable_entity.dart';
import 'installment_status.dart';
import 'owner_type.dart';

/// One due date's record within a [PaymentSchedule] — a fixed, distinct
/// document (unlike the older `Bill` model's single rolling occurrence).
/// Cumulative payments are cached on [amountPaid] (kept in sync by
/// `InstallmentRepository.applyPayment`); the `payments` subcollection of
/// [InstallmentPayment]s remains the source of truth, same "cached, not
/// truth" pattern as `Bill.amountPaid`/`Person.currentBalance`.
class Installment extends SoftDeletableEntity {
  Installment({
    required this.id,
    required this.scheduleId,
    required this.ownerType,
    required this.ownerId,
    required this.sequenceNumber,
    required this.dueDate,
    required this.amountDue,
    required this.createdAt,
    this.amountPaid = 0,
    this.isSkipped = false,
    this.principalPortion,
    this.interestPortion,
  });

  @override
  final String id;
  final String scheduleId;

  /// Denormalized from the owning [PaymentSchedule] so a future cross-owner
  /// query (e.g. every overdue installment regardless of loan) doesn't need
  /// an extra read per installment.
  final OwnerType ownerType;
  final String ownerId;

  /// 1-based position within the schedule, for display/ordering.
  final int sequenceNumber;
  DateTime dueDate;
  double amountDue;
  double amountPaid;
  bool isSkipped;

  /// Only populated when the owning schedule carries interest (currently:
  /// interest-bearing Loans). Null for Bills, split expenses, and
  /// non-interest loans. When non-null, principalPortion + interestPortion
  /// equals amountDue (to the cent) — the Lending layer, not this engine,
  /// owns that invariant, since the engine has no concept of "interest".
  final double? principalPortion;
  final double? interestPortion;

  final DateTime createdAt;

  double get remainingAmount => (amountDue - amountPaid).clamp(0, amountDue);

  /// This installment's current standing — see [InstallmentStatus].
  InstallmentStatus get status {
    if (amountPaid >= amountDue) return InstallmentStatus.paid;
    if (isSkipped) return InstallmentStatus.skipped;
    if (amountPaid > 0) return InstallmentStatus.partiallyPaid;

    final today = DateTime.now().dateOnly;
    if (dueDate.dateOnly.isBefore(today)) return InstallmentStatus.overdue;
    return InstallmentStatus.upcoming;
  }

  factory Installment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Installment(
      id: snapshot.id,
      scheduleId: data['scheduleId'] as String,
      ownerType: OwnerTypeX.fromName(data['ownerType'] as String),
      ownerId: data['ownerId'] as String,
      sequenceNumber: (data['sequenceNumber'] as num).toInt(),
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      amountDue: (data['amountDue'] as num).toDouble(),
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      isSkipped: data['isSkipped'] as bool? ?? false,
      principalPortion: (data['principalPortion'] as num?)?.toDouble(),
      interestPortion: (data['interestPortion'] as num?)?.toDouble(),
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
      'scheduleId': scheduleId,
      'ownerType': ownerType.name,
      'ownerId': ownerId,
      'sequenceNumber': sequenceNumber,
      'dueDate': Timestamp.fromDate(dueDate),
      'amountDue': amountDue,
      'amountPaid': amountPaid,
      'isSkipped': isSkipped,
      'principalPortion': principalPortion,
      'interestPortion': interestPortion,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
