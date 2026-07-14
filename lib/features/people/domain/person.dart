import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';

/// Someone you track a running money balance with — friend, family,
/// business contact. Whether they're a "creditor" (they owe you) or
/// "debtor" (you owe them) is never stored; it's derived from the sign of
/// [currentBalance] via [isCreditor]/[isDebtor], since the same person can
/// flip sides over time as ledger entries are added.
class Person extends SoftDeletableEntity {
  Person({
    required this.id,
    required this.name,
    required this.avatarColorValue,
    required this.openingBalance,
    required this.currentBalance,
    required this.createdAt,
    this.phone,
    this.email,
    this.notes = '',
  });

  @override
  final String id;
  String name;
  String? phone;
  String? email;
  String notes;
  int avatarColorValue;

  /// Set once at creation and never edited afterward — mirrors
  /// [Account.openingBalance]. Corrections after the fact go through an
  /// explicit, dated "Manual adjustment" ledger entry instead, so the
  /// timeline's starting point is never silently rewritten.
  final double openingBalance;

  /// Cached running balance (opening balance + every active ledger entry's
  /// signed amount), kept in sync by [PersonRepository.adjustBalance] on
  /// every ledger write — the ledger subcollection remains the source of
  /// truth; this is a read optimization, not a second ledger.
  double currentBalance;

  final DateTime createdAt;

  /// Positive balance: this person owes you money.
  bool get isCreditor => currentBalance > 0;

  /// Negative balance: you owe this person money.
  bool get isDebtor => currentBalance < 0;

  factory Person.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Person(
      id: snapshot.id,
      name: data['name'] as String,
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      notes: data['notes'] as String? ?? '',
      avatarColorValue: data['avatarColorValue'] as int,
      openingBalance: (data['openingBalance'] as num).toDouble(),
      currentBalance: (data['currentBalance'] as num).toDouble(),
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
      'phone': phone,
      'email': email,
      'notes': notes,
      'avatarColorValue': avatarColorValue,
      'openingBalance': openingBalance,
      'currentBalance': currentBalance,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
