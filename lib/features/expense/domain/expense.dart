import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'expense_participant.dart';
import 'split_type.dart';

/// An expense you paid, optionally split across other people (or assigned
/// entirely to one person — the degenerate single-participant case of the
/// same [splitType]/[participants] shape). Every expense also has a matching
/// [Transaction] (tracked by [transactionId]) for account-balance purposes —
/// [Expense] owns split/assignment metadata, [Transaction] owns the account
/// balance effect, so neither duplicates the other's source of truth.
class Expense extends SoftDeletableEntity {
  Expense({
    required this.id,
    required this.description,
    required this.totalAmount,
    required this.date,
    required this.categoryId,
    required this.accountId,
    required this.transactionId,
    required this.splitType,
    required this.participants,
    required this.createdAt,
    this.scheduleId,
    this.notes = '',
  });

  @override
  final String id;
  String description;
  double totalAmount;
  DateTime date;
  String categoryId;
  String accountId;

  /// The [Transaction] this expense posted for account-balance purposes.
  final String transactionId;

  /// Mutable so `ExpenseRepository.convertToSplit` can turn a plain
  /// ([SplitType.none]) expense into a split one after the fact, without
  /// touching [transactionId] — the account-balance effect never changes,
  /// only how the same total is divided among participants.
  SplitType splitType;

  /// Empty when [splitType] is [SplitType.none] (a plain, unsplit expense).
  List<ExpenseParticipant> participants;

  /// The [PaymentSchedule] (`OwnerType.splitExpense`) tracking participant
  /// settlements — null when [splitType] is [SplitType.none], since an
  /// unsplit expense has nothing to settle. Set once by
  /// `ExpenseRepository.convertToSplit` if a plain expense is later split;
  /// never cleared afterward.
  String? scheduleId;

  String notes;
  final DateTime createdAt;

  bool get isSplit => splitType != SplitType.none && participants.isNotEmpty;

  /// The permanent "Me" participant, if this expense has one — split
  /// expenses created before this field existed have none.
  ExpenseParticipant? get meParticipant => participants.where((p) => p.isMe).firstOrNull;

  /// How much of this expense was actually mine: the full amount for a
  /// plain or single-assignee expense (nobody else fronted any of it), or
  /// the "Me" participant's own share for a split expense. Split expenses
  /// with no "Me" participant (created before this field existed) report
  /// 0 rather than guessing, since that portion was never captured.
  double get myShare => !isSplit ? totalAmount : (meParticipant?.share ?? 0);

  /// The portion of this expense other people are responsible for.
  double get othersShare => totalAmount - myShare;

  /// Whether a transaction linked to [expense] (`null` if no `Expense`
  /// document exists yet) can still be turned into — or re-targeted as — a
  /// split/assignment via `ExpenseRepository.convertToSplit`/
  /// `.convertToAssigned`. [isExpenseTransaction] is the caller's
  /// `Transaction.type == TransactionType.expense` check, passed in rather
  /// than imported so this domain layer stays decoupled from the
  /// transactions feature's domain types. `false` for a non-expense
  /// transaction (nothing to assign/split) or an already-split/assigned
  /// expense (`convertToSplit`/`convertToAssigned` both reject re-converting
  /// one of those — use `ExpenseRepository.editExpense` instead, via
  /// `SplitExpenseFormSheet(editing: expense)`).
  ///
  /// Pulled out as a named, unit-testable function (rather than an inline
  /// boolean on `TransactionDetailScreen`) after a user report that turned
  /// out to be a mislabeled income transaction — the rule itself was
  /// correct, but nothing explained *why* the actions were hidden. Every
  /// caller should pair a `false` result with a visible reason, not a
  /// silently empty AppBar.
  static bool canReassign({required Expense? expense, required bool isExpenseTransaction}) {
    return (expense == null || !expense.isSplit) && isExpenseTransaction;
  }

  factory Expense.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Expense(
      id: snapshot.id,
      description: data['description'] as String,
      totalAmount: (data['totalAmount'] as num).toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      categoryId: data['categoryId'] as String,
      accountId: data['accountId'] as String,
      transactionId: data['transactionId'] as String,
      splitType: SplitTypeX.fromName(data['splitType'] as String),
      participants: (data['participants'] as List<dynamic>? ?? [])
          .map((p) => ExpenseParticipant.fromMap(p as Map<String, dynamic>))
          .toList(),
      scheduleId: data['scheduleId'] as String?,
      notes: data['notes'] as String? ?? '',
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
      'description': description,
      'totalAmount': totalAmount,
      'date': Timestamp.fromDate(date),
      'categoryId': categoryId,
      'accountId': accountId,
      'transactionId': transactionId,
      'splitType': splitType.name,
      'participants': participants.map((p) => p.toMap()).toList(),
      'scheduleId': scheduleId,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
