import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'transaction_type.dart';

/// A single income or expense movement against an [Account]. The dashboard,
/// history, reports, and account balances are all derived from these.
class Transaction extends SoftDeletableEntity {
  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.dateTime,
    required this.accountId,
    required this.categoryId,
    required this.createdAt,
    this.description = '',
    this.notes = '',
    this.receiptPurpose,
    this.transferId,
  });

  @override
  final String id;
  TransactionType type;
  double amount;
  DateTime dateTime;
  String accountId;
  String categoryId;
  String description;
  String notes;

  /// Set only when this transaction was created via `MoneyReceivedSheet` /
  /// `ReceiptClassificationRouter.classify` — stores the `ReceiptPurpose`
  /// name so the History screen can filter "Money received" precisely,
  /// rather than guessing from `notes` text. Null for every other
  /// transaction (manual entries, and the account-balance effect of a
  /// split/assigned `Expense`).
  final String? receiptPurpose;

  /// Set on both legs of a transfer between two of the user's own accounts
  /// (an expense leg on the source account + an income leg on the
  /// destination account, sharing this id) — see
  /// `TransactionRepository.createTransferPair`. Null for every other
  /// transaction. Aggregations that sum income/expense totals (Dashboard,
  /// Reports, Cash Flow, Budgets, Person balances) must exclude
  /// [isTransfer] transactions, or a transfer's two legs double-count into
  /// both totals even though no money actually left the user overall.
  final String? transferId;

  bool get isTransfer => transferId != null;

  final DateTime createdAt;

  /// The signed delta this transaction applies to its account's balance —
  /// the single source of truth for balance math, so the repository never
  /// has to duplicate "income adds, expense subtracts" logic.
  double get signedAmount => type == TransactionType.income ? amount : -amount;

  factory Transaction.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Transaction(
      id: snapshot.id,
      type: TransactionTypeX.fromName(data['type'] as String),
      amount: (data['amount'] as num).toDouble(),
      dateTime: (data['dateTime'] as Timestamp).toDate(),
      accountId: data['accountId'] as String,
      categoryId: data['categoryId'] as String,
      description: data['description'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      receiptPurpose: data['receiptPurpose'] as String?,
      transferId: data['transferId'] as String?,
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
      'dateTime': Timestamp.fromDate(dateTime),
      'accountId': accountId,
      'categoryId': categoryId,
      'description': description,
      'notes': notes,
      'receiptPurpose': receiptPurpose,
      'transferId': transferId,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
