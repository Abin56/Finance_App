import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';

/// A bank-issued credit facility shared by two or more [CreditCardProfile]s
/// that are really the same physical card issued on multiple networks (e.g.
/// a Visa and RuPay variant of one SBI card) — spending on either variant
/// draws down the same limit, exactly as the bank would treat it. Purely a
/// limit-holding entity: it has no linked [Account] of its own and is never
/// transacted against directly.
class SharedCreditLimit extends SoftDeletableEntity {
  SharedCreditLimit({
    required this.id,
    required this.name,
    required this.creditLimit,
    required this.createdAt,
  });

  @override
  final String id;

  /// User-entered label for the facility, e.g. "SBI" or "SBI Regalia" —
  /// distinct from any member card's own account name.
  String name;

  /// The shared limit every member [CreditCardProfile] draws from.
  double creditLimit;

  final DateTime createdAt;

  factory SharedCreditLimit.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return SharedCreditLimit(
      id: snapshot.id,
      name: data['name'] as String,
      creditLimit: (data['creditLimit'] as num).toDouble(),
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
      'creditLimit': creditLimit,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
