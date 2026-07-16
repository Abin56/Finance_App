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
    this.bankId,
    this.accountHolderName,
    this.notes,
    this.accountNumberLast4,
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

  /// References a [BankInfo] in the shared bank registry — display data
  /// (name, logo color) is always resolved live from there, never copied
  /// onto this entity, so a future branding correction applies everywhere
  /// automatically. Null for accounts with no bank picked yet (including
  /// every account created before this feature existed).
  String? bankId;

  /// Optional metadata — none of this feeds any calculation.
  String? accountHolderName;
  String? notes;

  /// Last 4 digits only; the full account number is never stored.
  String? accountNumberLast4;

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
      bankId: data['bankId'] as String?,
      accountHolderName: data['accountHolderName'] as String?,
      notes: data['notes'] as String?,
      accountNumberLast4: data['accountNumberLast4'] as String?,
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
      'bankId': bankId,
      'accountHolderName': accountHolderName,
      'notes': notes,
      'accountNumberLast4': accountNumberLast4,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
