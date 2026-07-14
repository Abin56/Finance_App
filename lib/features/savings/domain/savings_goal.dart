import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/num_extensions.dart';
import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';

/// A savings target the user is contributing toward over time — e.g. "New
/// laptop, ₹80,000 by December". [currentAmount] only ever moves via
/// [SavingsRepository.contribute], so every change is captured in
/// [editHistory] (the "Goal History" requirement).
class SavingsGoal extends SoftDeletableEntity {
  SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.createdAt,
    this.currentAmount = 0,
    this.dueDate,
    this.notes = '',
    this.isCompleted = false,
    this.isArchived = false,
  });

  @override
  final String id;
  String name;
  double targetAmount;
  double currentAmount;
  DateTime? dueDate;
  String notes;
  bool isCompleted;
  bool isArchived;
  final DateTime createdAt;

  double get progress => (currentAmount / targetAmount).clampedProgress;

  factory SavingsGoal.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return SavingsGoal(
      id: snapshot.id,
      name: data['name'] as String,
      targetAmount: (data['targetAmount'] as num).toDouble(),
      currentAmount: (data['currentAmount'] as num?)?.toDouble() ?? 0,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      notes: data['notes'] as String? ?? '',
      isCompleted: data['isCompleted'] as bool? ?? false,
      isArchived: data['isArchived'] as bool? ?? false,
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
      'name': name,
      'targetAmount': targetAmount,
      'currentAmount': currentAmount,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
      'notes': notes,
      'isCompleted': isCompleted,
      'isArchived': isArchived,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
