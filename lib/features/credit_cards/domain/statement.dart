import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/date_extensions.dart';
import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'statement_status.dart';

/// One closed billing cycle for a [CreditCardProfile] — materialized once
/// (see `StatementRepository.materializeIfDue`) from the transactions that
/// fell inside its window. [totalAmount]/[minimumDue] are the values at
/// materialization time; every screen/provider that displays a statement's
/// total must read it via `statementsWithLiveTotalsProvider` instead of
/// these fields directly, since a transaction inside an already-closed
/// period can still be soft-deleted, edited, or restored afterward and this
/// stored snapshot is never itself rewritten (see `StatementRepository.
/// totalFor`, which recomputes it live the same way it's computed for a new
/// statement). [amountPaid] (via [StatementPayment]s) and manually-logged
/// [interestCharged]/[lateFee] are the only fields safe to read directly, as
/// they're independent of the underlying transactions.
class Statement extends SoftDeletableEntity {
  Statement({
    required this.id,
    required this.cardId,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedDate,
    required this.dueDate,
    required this.totalAmount,
    required this.createdAt,
    this.minimumDue,
    this.amountPaid = 0,
    this.interestCharged,
    this.lateFee,
  });

  @override
  final String id;

  /// The [CreditCardProfile] this statement belongs to.
  final String cardId;

  final DateTime periodStart;
  final DateTime periodEnd;

  /// The date this statement closed/was generated — equal to [periodEnd].
  final DateTime generatedDate;

  final DateTime dueDate;

  /// Sum of every card-account [Transaction.amount] dated within
  /// `[periodStart, periodEnd]` at generation time — always the full
  /// transaction amount, unaffected by a later split/assignment (see
  /// `Expense.myShare`, which only reallocates who owes what, never the
  /// underlying transaction). Stale the moment one of those transactions is
  /// later deleted/edited/restored — see the class doc, use
  /// `StatementRepository.liveTotalFor` instead of reading this directly.
  final double totalAmount;

  /// Computed from `CreditCardProfile.minimumDuePercent` and [totalAmount]
  /// at generation time; null if that card tracks no minimum due. Subject
  /// to the same staleness as [totalAmount].
  final double? minimumDue;

  /// Cumulative [StatementPayment]s — same "cached, subcollection is
  /// truth" pattern as [Bill.amountPaid].
  double amountPaid;

  /// Optional manually-logged figures — this app has no interest/late-fee
  /// calculation engine, so these are user-entered, not computed, and are
  /// simply omitted from any UI when null.
  double? interestCharged;
  double? lateFee;

  final DateTime createdAt;

  double get remainingAmount => (totalAmount - amountPaid).clamp(0, totalAmount);

  /// Whether [date] falls within `[periodStart, periodEnd]` (inclusive,
  /// date-only) — the single place every screen/provider checks "is this
  /// transaction inside this statement" instead of each re-deriving it.
  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final end = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// A copy with [totalAmount]/[minimumDue] replaced — used by
  /// `statementsWithLiveTotalsProvider` to correct this materialized
  /// statement's stored (possibly stale) total against what its period's
  /// transactions currently sum to, without touching Firestore or any other
  /// field (including [amountPaid], [editHistory], etc.).
  Statement withLiveTotal(double liveTotalAmount, double? liveMinimumDue) {
    return Statement(
      id: id,
      cardId: cardId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      generatedDate: generatedDate,
      dueDate: dueDate,
      totalAmount: liveTotalAmount,
      minimumDue: liveMinimumDue,
      createdAt: createdAt,
      amountPaid: amountPaid,
      interestCharged: interestCharged,
      lateFee: lateFee,
    )
      ..deletedAt = deletedAt
      ..lastEditedAt = lastEditedAt
      ..editHistory = editHistory;
  }

  StatementStatus get status {
    if (amountPaid >= totalAmount) return StatementStatus.paid;
    if (amountPaid > 0) return StatementStatus.partiallyPaid;

    final today = DateTime.now().dateOnly;
    final due = dueDate.dateOnly;
    if (due.isBefore(today)) return StatementStatus.overdue;
    if (due.difference(today).inDays <= 7) return StatementStatus.dueSoon;
    return StatementStatus.pending;
  }

  factory Statement.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Statement(
      id: snapshot.id,
      cardId: data['cardId'] as String,
      periodStart: (data['periodStart'] as Timestamp).toDate(),
      periodEnd: (data['periodEnd'] as Timestamp).toDate(),
      generatedDate: (data['generatedDate'] as Timestamp).toDate(),
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      totalAmount: (data['totalAmount'] as num).toDouble(),
      minimumDue: (data['minimumDue'] as num?)?.toDouble(),
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      interestCharged: (data['interestCharged'] as num?)?.toDouble(),
      lateFee: (data['lateFee'] as num?)?.toDouble(),
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
      'cardId': cardId,
      'periodStart': Timestamp.fromDate(periodStart),
      'periodEnd': Timestamp.fromDate(periodEnd),
      'generatedDate': Timestamp.fromDate(generatedDate),
      'dueDate': Timestamp.fromDate(dueDate),
      'totalAmount': totalAmount,
      'minimumDue': minimumDue,
      'amountPaid': amountPaid,
      'interestCharged': interestCharged,
      'lateFee': lateFee,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
