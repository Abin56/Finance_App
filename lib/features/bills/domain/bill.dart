import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/models/soft_deletable_entity.dart';
import 'bill_recurrence.dart';

/// A recurring or one-time payment obligation's template — rent, a
/// subscription, a utility bill. Describes what occurrence to materialize
/// next ([nextDueDate]/[amount]/[recurrence]); the occurrence itself (due
/// date, progress, paid/skipped state) lives in its own immutable
/// [BillOccurrence] document, one per billing cycle (see
/// `BillOccurrenceRepository`). This template is never mutated by a
/// payment or rollover — only [BillRepository.editBill] changes it, and
/// only [BillOccurrenceRepository] advances [nextDueDate] once a new
/// occurrence is materialized.
class Bill extends SoftDeletableEntity {
  Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.nextDueDate,
    required this.recurrence,
    required this.createdAt,
    this.accountId,
    this.categoryId,
    this.customIntervalDays,
    this.reminderOffsets = const [],
    this.notes = '',
  });

  @override
  final String id;
  String name;
  double amount;

  /// The due date the next [BillOccurrence] should be materialized at —
  /// advanced by [BillOccurrenceRepository] each time a new occurrence is
  /// created from this template, never by a payment or edit directly.
  DateTime nextDueDate;
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

  final DateTime createdAt;

  factory Bill.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data()!;
    return Bill(
      id: snapshot.id,
      name: data['name'] as String,
      amount: (data['amount'] as num).toDouble(),
      // Legacy documents (written before the one-occurrence-per-cycle
      // migration) never wrote `nextDueDate` — they only ever had
      // `dueDate`, which described the same "when's the next occurrence"
      // concept under the old single-document model. Falling back to it
      // here means a legacy Bill parses correctly forever, with no forced
      // rewrite — see `BillOccurrenceRepository.ensureCurrentOccurrence`
      // for the one-time adoption of the rest of that legacy state.
      nextDueDate: (data['nextDueDate'] as Timestamp?)?.toDate() ?? (data['dueDate'] as Timestamp).toDate(),
      recurrence: BillRecurrenceX.fromName(data['recurrence'] as String),
      accountId: data['accountId'] as String?,
      categoryId: data['categoryId'] as String?,
      customIntervalDays: (data['customIntervalDays'] as num?)?.toInt(),
      reminderOffsets: (data['reminderOffsets'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
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
      'name': name,
      'amount': amount,
      'nextDueDate': Timestamp.fromDate(nextDueDate),
      'recurrence': recurrence.name,
      'accountId': accountId,
      'categoryId': categoryId,
      'customIntervalDays': customIntervalDays,
      'reminderOffsets': reminderOffsets,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt!),
      'lastEditedAt': lastEditedAt == null ? null : Timestamp.fromDate(lastEditedAt!),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
    };
  }
}
