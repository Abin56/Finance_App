import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/services/reminder_notification_service.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/reminder_offset_label.dart';
import '../domain/bill.dart';
import '../domain/bill_occurrence.dart';
import '../domain/bill_recurrence.dart';
import '../domain/bill_status.dart';
import '../domain/payment_record.dart';
import 'bill_repository.dart';

/// Legacy in-progress state read straight off a pre-migration [Bill]
/// document's raw fields (`amountPaid`/`isSkipped`) — fields [Bill] itself
/// no longer parses, since they're not template concerns. Only meaningful
/// once, the first time a legacy bill is read after this migration ships.
class LegacyBillOccurrenceState {
  const LegacyBillOccurrenceState({required this.amountPaid, required this.isSkipped});

  final double amountPaid;
  final bool isSkipped;

  static const none = LegacyBillOccurrenceState(amountPaid: 0, isSkipped: false);

  bool get hasProgress => amountPaid > 0 || isSkipped;

  /// Reads `amountPaid`/`isSkipped` off the raw (unconverted) document at
  /// [billDoc], if it exists — a pre-migration document written before
  /// [BillOccurrence] existed always has these fields; a bill created after
  /// this migration never does, so this returns [none] for it.
  static Future<LegacyBillOccurrenceState> readFrom(DocumentReference<Map<String, dynamic>> billDoc) async {
    final snapshot = await billDoc.get();
    final data = snapshot.data();
    if (data == null) return none;
    return LegacyBillOccurrenceState(
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      isSkipped: data['isSkipped'] as bool? ?? false,
    );
  }
}

/// [BillOccurrence] persistence, built around the same "lazy generation,
/// no background jobs" pattern `StatementRepository` uses for Credit Cards
/// — [ensureCurrentOccurrence] is the single entrypoint the provider layer
/// calls whenever a bill's screen is opened. It is idempotent by
/// construction (existence of at least one occurrence is the only guard
/// needed) and folds three cases into one call: adopting a pre-migration
/// bill's in-progress state into its first occurrence, materializing a
/// fresh occurrence for a brand-new bill, and rolling a settled occurrence
/// forward into the next one — there is no separate migration step to
/// remember to run.
class BillOccurrenceRepository extends FirestoreCrudRepository<BillOccurrence> {
  BillOccurrenceRepository(
    super.collection,
    this.billRepository,
    this.legacyBillDoc,
    this.legacyPaymentsCollection,
  );

  final BillRepository billRepository;

  /// Raw (unconverted) reference to this occurrence collection's parent
  /// [Bill] document — used only to read legacy `amountPaid`/`isSkipped`
  /// during one-time adoption; never written to.
  final DocumentReference<Map<String, dynamic>> legacyBillDoc;

  /// Raw (unconverted) reference to the bill's `payments` subcollection —
  /// used only to backfill `occurrenceId` on pre-migration [PaymentRecord]s
  /// during one-time adoption, without creating a dependency on
  /// `PaymentRepository` (which itself depends on this repository, so a
  /// direct reference back would be circular).
  final CollectionReference<Map<String, dynamic>> legacyPaymentsCollection;

  /// Returns the occurrence that represents "current" for [bill] —
  /// materializing, adopting legacy state, or rolling forward as needed.
  /// [existing] and [legacyPayments] are passed in already-loaded (from the
  /// provider layer's streams) so this never issues its own reads beyond
  /// the one-time legacy-field lookup.
  Future<BillOccurrence> ensureCurrentOccurrence(
    Bill bill,
    List<BillOccurrence> existing, {
    List<PaymentRecord> legacyPayments = const [],
    DateTime? now,
  }) async {
    if (existing.isNotEmpty) {
      final latest = existing.reduce((a, b) => a.dueDate.isAfter(b.dueDate) ? a : b);
      final isSettled = latest.status == BillStatus.paid || latest.status == BillStatus.skipped;
      if (!isSettled) return latest;
      if (bill.recurrence == BillRecurrence.oneTime) return latest;
      return _rollForward(bill, latest, now: now);
    }

    final legacy = await LegacyBillOccurrenceState.readFrom(legacyBillDoc);
    if (legacy.hasProgress || legacyPayments.isNotEmpty) {
      return _adoptLegacy(bill, legacy, legacyPayments);
    }
    return _materializeFirst(bill, now: now);
  }

  /// Adopts a pre-migration bill's in-progress state into exactly one new
  /// [BillOccurrence], then backfills every existing [PaymentRecord]'s
  /// `occurrenceId` to point at it. Runs at most once per bill — guarded by
  /// [ensureCurrentOccurrence]'s "existing is non-empty" check, so a second
  /// call for the same bill never reaches here again.
  Future<BillOccurrence> _adoptLegacy(
    Bill bill,
    LegacyBillOccurrenceState legacy,
    List<PaymentRecord> legacyPayments,
  ) async {
    final occurrence = BillOccurrence(
      id: IdGenerator.generate(),
      billId: bill.id,
      dueDate: bill.nextDueDate,
      amount: bill.amount,
      amountPaid: legacy.amountPaid,
      isSkipped: legacy.isSkipped,
      createdAt: DateTime.now(),
    );
    await add(occurrence.id, occurrence);

    for (final payment in legacyPayments) {
      if (payment.occurrenceId != null) continue;
      await legacyPaymentsCollection.doc(payment.id).update({'occurrenceId': occurrence.id});
    }

    _scheduleReminders(bill, occurrence);
    return occurrence;
  }

  /// Materializes the very first occurrence for a brand-new bill, at
  /// [Bill.nextDueDate] — no prior occurrence exists yet, so there is
  /// nothing to advance the template past.
  Future<BillOccurrence> _materializeFirst(Bill bill, {DateTime? now}) async {
    final occurrence = BillOccurrence(
      id: IdGenerator.generate(),
      billId: bill.id,
      dueDate: bill.nextDueDate,
      amount: bill.amount,
      createdAt: now ?? DateTime.now(),
    );
    await add(occurrence.id, occurrence);
    _scheduleReminders(bill, occurrence);
    return occurrence;
  }

  /// [settled] has just become paid/skipped — advances the template's
  /// [Bill.nextDueDate] past it, then materializes the next occurrence at
  /// that new date. Unlike [_materializeFirst], advancing happens *before*
  /// creating the new occurrence, since [settled]'s own due date is what's
  /// being advanced past, not the occurrence about to be created.
  Future<BillOccurrence> _rollForward(Bill bill, BillOccurrence settled, {DateTime? now}) async {
    final next = bill.recurrence.nextDueDate(settled.dueDate, customDays: bill.customIntervalDays);
    await billRepository.advanceNextDueDate(bill, next);

    final occurrence = BillOccurrence(
      id: IdGenerator.generate(),
      billId: bill.id,
      dueDate: next,
      amount: bill.amount,
      createdAt: now ?? DateTime.now(),
    );
    await add(occurrence.id, occurrence);
    _scheduleReminders(bill, occurrence);
    return occurrence;
  }

  /// Applies a payment delta toward [occurrence], clamped so
  /// [BillOccurrence.amountPaid] never exceeds [BillOccurrence.amount].
  /// Once settled, this occurrence is never written to again — the next
  /// [ensureCurrentOccurrence] call materializes a new one rather than
  /// rolling this document over in place.
  Future<void> applyPayment(BillOccurrence occurrence, double delta) async {
    if (delta == 0) return;
    final newAmountPaid = (occurrence.amountPaid + delta).clamp(0, occurrence.amount).toDouble();
    occurrence.recordEdit(
      field: 'amountPaid',
      oldValue: occurrence.amountPaid.toString(),
      newValue: newAmountPaid.toString(),
    );
    occurrence.amountPaid = newAmountPaid;
    await update(occurrence);
    if (newAmountPaid >= occurrence.amount) _cancelReminders(occurrence.id);
  }

  /// Marks [occurrence] fully paid without an explicit payment record —
  /// "quick mark as paid" without entering an amount.
  Future<void> markPaid(BillOccurrence occurrence) async {
    if (occurrence.amountPaid >= occurrence.amount) return;
    occurrence.recordEdit(
      field: 'amountPaid',
      oldValue: occurrence.amountPaid.toString(),
      newValue: occurrence.amount.toString(),
    );
    occurrence.amountPaid = occurrence.amount;
    await update(occurrence);
    _cancelReminders(occurrence.id);
  }

  /// Marks [occurrence] skipped (not paid, not counted as overdue).
  Future<void> skipOccurrence(BillOccurrence occurrence) async {
    if (occurrence.isSkipped) return;
    occurrence.recordEdit(field: 'isSkipped', oldValue: 'false', newValue: 'true');
    occurrence.isSkipped = true;
    await update(occurrence);
    _cancelReminders(occurrence.id);
  }

  Future<void> unskip(BillOccurrence occurrence) async {
    if (!occurrence.isSkipped) return;
    occurrence.recordEdit(field: 'isSkipped', oldValue: 'true', newValue: 'false');
    occurrence.isSkipped = false;
    await update(occurrence);
  }

  /// Best-effort, fire-and-forget — a notification scheduling failure must
  /// never block or fail a Firestore write. Keyed by [occurrence.id] (not
  /// the bill's id), since multiple occurrences can now coexist and each
  /// needs its own independently cancellable reminder.
  void _scheduleReminders(Bill bill, BillOccurrence occurrence) {
    if (occurrence.status == BillStatus.paid || occurrence.status == BillStatus.skipped) return;
    ReminderNotificationService.reschedule(
      ownerId: occurrence.id,
      title: bill.name,
      bodyBuilder: (offset) => '${reminderOffsetLabel(offset)} — due ${occurrence.dueDate.day}/${occurrence.dueDate.month}',
      dueDate: occurrence.dueDate,
      offsets: bill.reminderOffsets,
    ).catchError((_) {});
  }

  void _cancelReminders(String occurrenceId) {
    ReminderNotificationService.cancel(occurrenceId).catchError((_) {});
  }
}
