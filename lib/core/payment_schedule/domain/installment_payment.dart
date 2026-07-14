import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/audit_entry.dart';
import '../../models/soft_deletable_entity.dart';
import 'owner_type.dart';

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
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
