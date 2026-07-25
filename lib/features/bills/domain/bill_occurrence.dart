import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/date_extensions.dart';
import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'bill_status.dart';

/// One billing cycle of a [Bill] — a single due date, its own amount
/// snapshot, and its own paid/skipped progress. Immutable once its
/// [status] becomes [BillStatus.paid] or [BillStatus.skipped]: nothing
/// after that point writes to [amountPaid]/[isSkipped]/[dueDate] again,
/// mirroring how a closed `Statement` is never rewritten once materialized.
/// A [Bill] template only ever describes what occurrence to materialize
/// next ([Bill.nextDueDate]/[Bill.amount]) — it never holds "the current"
/// occurrence's progress itself.
class BillOccurrence extends SoftDeletableEntity {
  BillOccurrence({
    required this.id,
    required this.billId,
    required this.dueDate,
    required this.amount,
    required this.createdAt,
    this.amountPaid = 0,
    this.isSkipped = false,
  });

  @override
  final String id;

  /// The [Bill] template this occurrence belongs to.
  final String billId;

  final DateTime dueDate;

  /// Snapshot of the template's `amount` at the moment this occurrence was
  /// materialized — later edits to `Bill.amount` never change an already
  /// materialized occurrence.
  final double amount;

  /// Cumulative payments applied to this occurrence. The `payments`
  /// subcollection (scoped by `PaymentRecord.occurrenceId`) is the source
  /// of truth; this is a read optimization kept in sync by
  /// [BillOccurrenceRepository.applyPayment] — same "cached, subcollection
  /// is truth" pattern as [Bill.amountPaid] used to be.
  double amountPaid;

  bool isSkipped;

  final DateTime createdAt;

  /// This occurrence's standing — see [BillStatus].
  BillStatus get status {
    if (amountPaid >= amount) return BillStatus.paid;
    if (isSkipped) return BillStatus.skipped;
    if (amountPaid > 0) return BillStatus.partiallyPaid;

    final today = DateTime.now().dateOnly;
    final due = dueDate.dateOnly;
    if (due.isBefore(today)) return BillStatus.overdue;
    if (due.isAtSameMomentAs(today)) return BillStatus.dueToday;
    return BillStatus.upcoming;
  }

  double get remainingAmount => (amount - amountPaid).clamp(0, amount);

  factory BillOccurrence.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return BillOccurrence(
      id: snapshot.id,
      billId: data['billId'] as String,
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      amount: (data['amount'] as num).toDouble(),
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      isSkipped: data['isSkipped'] as bool? ?? false,
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
      'billId': billId,
      'dueDate': Timestamp.fromDate(dueDate),
      'amount': amount,
      'amountPaid': amountPaid,
      'isSkipped': isSkipped,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
