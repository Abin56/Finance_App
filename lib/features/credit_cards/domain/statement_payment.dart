import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';

/// A single payment applied toward a [Statement]'s total. Append-only like
/// [PaymentRecord] — soft-delete (which reverses its effect on
/// [Statement.amountPaid]) and restore are the only ways its effect
/// changes. [transactionId] links to the outgoing [Transaction] this
/// payment created from [sourceAccountId] — the actual account-balance
/// effect, mirroring how [Expense.transactionId] owns balance effects
/// rather than the domain-specific record duplicating it.
class StatementPayment extends SoftDeletableEntity {
  StatementPayment({
    required this.id,
    required this.statementId,
    required this.amount,
    required this.date,
    required this.sourceAccountId,
    required this.transactionId,
    required this.createdAt,
    this.note = '',
  });

  @override
  final String id;
  final String statementId;

  /// Always positive.
  final double amount;
  final DateTime date;

  /// The account the payment was made from (e.g. a bank account).
  final String sourceAccountId;

  /// The outgoing [Transaction] this payment posted — the account-balance
  /// effect, never duplicated here.
  final String transactionId;
  final String note;
  final DateTime createdAt;

  factory StatementPayment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return StatementPayment(
      id: snapshot.id,
      statementId: data['statementId'] as String,
      amount: (data['amount'] as num).toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      sourceAccountId: data['sourceAccountId'] as String,
      transactionId: data['transactionId'] as String,
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
      'statementId': statementId,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'sourceAccountId': sourceAccountId,
      'transactionId': transactionId,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
