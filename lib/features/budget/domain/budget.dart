import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'budget_type.dart';

/// An ongoing spending limit — daily, monthly, or monthly-per-category
/// (when [categoryId] is set). Holds only the limit amount; "used" and
/// "remaining" are always computed live from transactions in the current
/// period rather than stored here, so a new day/month "resets" for free —
/// there's nothing to reset.
class Budget extends SoftDeletableEntity {
  Budget({
    required this.id,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.categoryId,
  });

  @override
  final String id;
  BudgetType type;
  double amount;
  String? categoryId;
  final DateTime createdAt;

  factory Budget.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Budget(
      id: snapshot.id,
      type: BudgetTypeX.fromName(data['type'] as String),
      amount: (data['amount'] as num).toDouble(),
      categoryId: data['categoryId'] as String?,
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
      'type': type.name,
      'amount': amount,
      'categoryId': categoryId,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
