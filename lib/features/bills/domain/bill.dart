import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/date_extensions.dart';
import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'bill_recurrence.dart';
import 'bill_status.dart';

/// A recurring or one-time payment obligation — rent, a subscription, a
/// utility bill. Holds only the current occurrence's limit and progress
/// ([amount]/[amountPaid]); once fully paid or skipped, a recurring bill's
/// [dueDate]/[amountPaid]/[isSkipped] roll forward to the next occurrence
/// (see [BillRepository]) rather than creating a new document per
/// occurrence — one document is the bill's whole lifetime.
class Bill extends SoftDeletableEntity {
  Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.dueDate,
    required this.recurrence,
    required this.createdAt,
    this.accountId,
    this.categoryId,
    this.customIntervalDays,
    this.reminderOffsets = const [],
    this.notes = '',
    this.amountPaid = 0,
    this.isSkipped = false,
  });

  @override
  final String id;
  String name;
  double amount;
  DateTime dueDate;
  BillRecurrence recurrence;
  String? accountId;
  String? categoryId;

  /// Only meaningful (and required by [BillRepository.createBill]) when
  /// [recurrence] is [BillRecurrence.custom].
  int? customIntervalDays;

  /// Days-before-due to fire a reminder — e.g. `[0, 1, 3, 7]` for
  /// Today/Tomorrow/3-days-before/7-days-before. Empty means no reminders.
  List<int> reminderOffsets;
  String notes;

  /// Cumulative payments applied to the *current* occurrence. Reset to 0
  /// when a recurring bill rolls over. The `payments` subcollection is the
  /// source of truth; this is a read optimization kept in sync by
  /// [BillRepository.applyPayment] — same "cached, subcollection is truth"
  /// pattern as [Person.currentBalance].
  double amountPaid;

  /// Whether the current occurrence was explicitly skipped rather than
  /// paid. Reset to false on rollover, same as [amountPaid].
  bool isSkipped;

  final DateTime createdAt;

  /// This occurrence's current standing — see [BillStatus].
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

  factory Bill.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Bill(
      id: snapshot.id,
      name: data['name'] as String,
      amount: (data['amount'] as num).toDouble(),
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      recurrence: BillRecurrenceX.fromName(data['recurrence'] as String),
      accountId: data['accountId'] as String?,
      categoryId: data['categoryId'] as String?,
      customIntervalDays: (data['customIntervalDays'] as num?)?.toInt(),
      reminderOffsets: (data['reminderOffsets'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
      notes: data['notes'] as String? ?? '',
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
      'name': name,
      'amount': amount,
      'dueDate': Timestamp.fromDate(dueDate),
      'recurrence': recurrence.name,
      'accountId': accountId,
      'categoryId': categoryId,
      'customIntervalDays': customIntervalDays,
      'reminderOffsets': reminderOffsets,
      'notes': notes,
      'amountPaid': amountPaid,
      'isSkipped': isSkipped,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
