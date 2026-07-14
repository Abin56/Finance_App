import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';

/// A single payment applied toward a [Bill]'s current occurrence.
/// Append-only like [LedgerEntry] — soft-delete (which reverses its effect
/// on [Bill.amountPaid]) and restore are the only ways its effect changes.
class PaymentRecord extends SoftDeletableEntity {
  PaymentRecord({
    required this.id,
    required this.billId,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.note = '',
  });

  @override
  final String id;
  final String billId;

  /// Always positive — payments only ever add toward [Bill.amountPaid].
  final double amount;
  final DateTime date;
  final String note;
  final DateTime createdAt;

  factory PaymentRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return PaymentRecord(
      id: snapshot.id,
      billId: data['billId'] as String,
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
      'billId': billId,
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
