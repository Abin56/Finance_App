import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'account_type.dart';

/// A money source the user tracks — Cash Wallet, a specific bank account,
/// a business account, etc. Every transaction (from Milestone 3 onward)
/// belongs to exactly one account, and the dashboard sums these for net worth.
class Account extends SoftDeletableEntity {
  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    required this.currentBalance,
    required this.colorValue,
    required this.createdAt,
    this.isDefault = false,
  });

  @override
  final String id;
  String name;
  AccountType type;
  double openingBalance;
  double currentBalance;
  int colorValue;
  bool isDefault;
  final DateTime createdAt;

  /// Document id is sourced from `snapshot.id` (Firestore's own enforced
  /// uniqueness), not a body field, so the two can never drift apart.
  factory Account.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Account(
      id: snapshot.id,
      name: data['name'] as String,
      type: AccountTypeX.fromName(data['type'] as String),
      openingBalance: (data['openingBalance'] as num).toDouble(),
      currentBalance: (data['currentBalance'] as num).toDouble(),
      colorValue: data['colorValue'] as int,
      isDefault: data['isDefault'] as bool? ?? false,
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
      'type': type.name,
      'openingBalance': openingBalance,
      'currentBalance': currentBalance,
      'colorValue': colorValue,
      'isDefault': isDefault,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
