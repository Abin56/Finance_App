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
    this.excludeFromCalculations = false,
    this.accountingMonth,
    this.linkedPersonId,
    this.owesPersonToggle = false,
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

  /// When true, this transaction still appears in History/Search/Details
  /// but must be excluded from every balance/total/report — a reference-only
  /// entry (e.g. a reimbursement, a duplicate already tracked elsewhere).
  bool excludeFromCalculations;

  /// Which month this transaction counts toward for monthly aggregations —
  /// null means "use [dateTime]'s own month" (the common case). Always
  /// truncated to the first of a month; never affects [dateTime] itself,
  /// History ordering, or Search. See [effectiveMonth].
  DateTime? accountingMonth;

  /// Optional reference to a [Person] this transaction is associated with —
  /// e.g. "lunch for Rahul" — purely descriptive: unlike an [Expense]'s
  /// `participants`, setting this never creates a ledger entry, split, loan,
  /// or EMI, and never affects any balance. Null for the overwhelming
  /// majority of transactions.
  String? linkedPersonId;

  /// Whether [linkedPersonId] represents money they owe back, rather than a
  /// plain reference — only meaningful when [linkedPersonId] is non-null,
  /// always `false` otherwise. When `true`, a single-participant `Expense`
  /// (created/maintained via `ExpenseRepository.assignToPerson`/
  /// `convertToAssigned`/`editExpense`) owns the actual ledger/balance
  /// effect for [linkedPersonId] — this flag exists purely so
  /// `AddExpenseScreen` knows which repository path a save/edit should take;
  /// it never drives balance math directly (see `ExpenseRepository`, the
  /// single place `LedgerEntry`s for expenses are ever created).
  bool owesPersonToggle;

  final DateTime createdAt;

  /// The signed delta this transaction applies to its account's balance —
  /// the single source of truth for balance math, so the repository never
  /// has to duplicate "income adds, expense subtracts" logic.
  double get signedAmount => type == TransactionType.income ? amount : -amount;

  /// The month every monthly aggregation (Dashboard, Reports, Budgets, Cash
  /// Flow) must bucket this transaction under, instead of [dateTime]'s own
  /// month — [accountingMonth] if set, else [dateTime]'s month.
  DateTime get effectiveMonth => accountingMonth ?? DateTime(dateTime.year, dateTime.month);

  /// The signed delta this transaction actually applies to its account's
  /// balance — [signedAmount], or zero when [excludeFromCalculations] is
  /// true. The single source of truth for every balance adjustment, so an
  /// excluded transaction can never partially affect a balance.
  double get balanceEffect => excludeFromCalculations ? 0 : signedAmount;

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
      excludeFromCalculations: data['excludeFromCalculations'] as bool? ?? false,
      accountingMonth: (data['accountingMonth'] as Timestamp?)?.toDate(),
      linkedPersonId: data['linkedPersonId'] as String?,
      owesPersonToggle: data['owesPersonToggle'] as bool? ?? false,
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
      'excludeFromCalculations': excludeFromCalculations,
      'accountingMonth': accountingMonth == null ? null : Timestamp.fromDate(accountingMonth!),
      'linkedPersonId': linkedPersonId,
      'owesPersonToggle': owesPersonToggle,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
