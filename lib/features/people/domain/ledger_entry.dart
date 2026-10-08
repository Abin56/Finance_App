import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'ledger_entry_type.dart';

/// A single movement in a [Person]'s ledger — append-only in the general
/// case (soft-delete, which reverses its balance effect, and restore are
/// the usual ways its effect on the running balance changes), with one
/// deliberate exception: [LedgerRepository.editEntryAmount] corrects
/// [amount] in place when the split/assigned `Expense` backing this entry
/// is edited, so the same history line the user tapped reflects the new
/// amount instead of leaving it stale alongside a separate adjustment line.
/// Every other field stays fixed for the entry's lifetime.
class LedgerEntry extends SoftDeletableEntity {
  LedgerEntry({
    required this.id,
    required this.personId,
    required this.type,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.note = '',
    this.transactionRef,
    this.increasesBalance = true,
    this.parentEntryId,
    this.sourceKind,
    this.obligationRef,
    this.receivedStatus,
    this.paymentId,
    this.installmentPaymentRef,
    this.incomeTransactionRef,
  });

  @override
  final String id;
  final String personId;
  final LedgerEntryType type;

  /// Always positive — direction comes from [type] (via [signFor]) for
  /// every type except [LedgerEntryType.adjustment], where [increasesBalance]
  /// carries the direction instead (an adjustment can correct the balance
  /// either way). Mutable only via [LedgerRepository.editEntryAmount].
  double amount;
  final DateTime date;
  final String note;

  /// Only meaningful for [LedgerEntryType.adjustment] — whether this
  /// correction increases or decreases the person's balance. Ignored for
  /// every other type, whose direction is fixed by [LedgerEntryType.signFor].
  final bool increasesBalance;

  /// Optional link to a [Transaction.id] — e.g. a repayment that also hit
  /// an account transaction. Stored but not validated against the
  /// Transactions collection in this milestone.
  final String? transactionRef;

  // --- Settlement linkage (shared with the web app — see the web
  // `lib/models/person.ts`). Every field is read AND written back, so a
  // full-document `set()` from this app (edit / soft-delete / restore) can
  // never strip a link the web app wrote. Stripping them used to detach a
  // settlement from the obligation it paid, reopening it and losing its
  // payment history and Undo.

  /// For a "receivedBack"/"repaid" settlement: the "gave"/"borrowed" entry it settles.
  final String? parentEntryId;

  /// Explicit origin: manual, splitExpense, assignedExpense, emiInstallment,
  /// loanInstallment, advance. Null on legacy entries.
  final String? sourceKind;

  /// Stable key of a derived obligation this entry settles, e.g. `emi-inst:{id}`.
  final String? obligationRef;

  /// "yetToReceive" / "received" — a settlement marker only, never balance math.
  final String? receivedStatus;

  /// Groups every entry written by one Record Payment (one real payment).
  final String? paymentId;

  /// Split-share tracking payment this entry wrote: `{scheduleId}/{installmentId}/{paymentId}`.
  final String? installmentPaymentRef;

  /// When part of the payment was recorded as separate income: that Income transaction.
  final String? incomeTransactionRef;

  /// An advance — money paid ahead of any obligation (held, not pending).
  bool get isAdvance => sourceKind == 'advance';

  final DateTime createdAt;

  /// The signed delta this entry applies (and applied) to its person's
  /// running balance — the single source of truth [LedgerRepository] uses
  /// both when posting the entry and when reversing it on soft-delete, so
  /// the two can never disagree about which direction this entry moved
  /// the balance.
  double get signedAmount => type == LedgerEntryType.adjustment
      ? (increasesBalance ? amount : -amount)
      : type.signFor(amount);

  factory LedgerEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return LedgerEntry(
        id: snapshot.id,
        personId: data['personId'] as String,
        type: LedgerEntryTypeX.fromName(data['type'] as String),
        amount: (data['amount'] as num).toDouble(),
        date: (data['date'] as Timestamp).toDate(),
        note: data['note'] as String? ?? '',
        transactionRef: data['transactionRef'] as String?,
        increasesBalance: data['increasesBalance'] as bool? ?? true,
        createdAt: (data['createdAt'] as Timestamp).toDate(),
        parentEntryId: data['parentEntryId'] as String?,
        sourceKind: data['sourceKind'] as String?,
        obligationRef: data['obligationRef'] as String?,
        receivedStatus: data['receivedStatus'] as String?,
        paymentId: data['paymentId'] as String?,
        installmentPaymentRef: data['installmentPaymentRef'] as String?,
        incomeTransactionRef: data['incomeTransactionRef'] as String?,
      )
      ..deletedAt = (data['deletedAt'] as Timestamp?)?.toDate()
      ..lastEditedAt = (data['lastEditedAt'] as Timestamp?)?.toDate()
      ..editHistory = (data['editHistory'] as List<dynamic>? ?? [])
          .map((e) => AuditEntry.fromMap(e as Map<String, dynamic>))
          .toList();
  }

  Map<String, dynamic> toFirestore() {
    return {
      'personId': personId,
      'type': type.name,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'note': note,
      'transactionRef': transactionRef,
      'increasesBalance': increasesBalance,
      'createdAt': Timestamp.fromDate(createdAt),
      'parentEntryId': parentEntryId,
      if (sourceKind != null) 'sourceKind': sourceKind,
      if (obligationRef != null) 'obligationRef': obligationRef,
      if (receivedStatus != null) 'receivedStatus': receivedStatus,
      if (paymentId != null) 'paymentId': paymentId,
      if (installmentPaymentRef != null)
        'installmentPaymentRef': installmentPaymentRef,
      if (incomeTransactionRef != null)
        'incomeTransactionRef': incomeTransactionRef,
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null
          ? null
          : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
