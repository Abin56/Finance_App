import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/reminder_notification_service.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/reminder_offset_label.dart';
import '../domain/bill.dart';
import '../domain/bill_recurrence.dart';

/// Bill-specific persistence on top of the generic CRUD/soft-delete
/// repository, plus payment-sync (the hook [PaymentRepository] calls on
/// every payment write, mirroring [PersonRepository.adjustBalance]) and
/// recurrence rollover.
class BillRepository extends FirestoreCrudRepository<Bill> {
  BillRepository(super.collection);

  @override
  Future<void> softDelete(Bill entity) async {
    await super.softDelete(entity);
    _cancelReminders(entity.id);
  }

  @override
  Future<void> restore(Bill entity) async {
    await super.restore(entity);
    _scheduleReminders(entity);
  }

  @override
  Future<void> permanentlyDelete(Bill entity) async {
    await super.permanentlyDelete(entity);
    _cancelReminders(entity.id);
  }

  Future<Bill> createBill({
    required String name,
    required double amount,
    required DateTime dueDate,
    required BillRecurrence recurrence,
    String? accountId,
    String? categoryId,
    int? customIntervalDays,
    List<int> reminderOffsets = const [],
    String notes = '',
  }) async {
    if (amount <= 0) {
      throw const AppException('Bill amount must be greater than 0');
    }
    if (recurrence == BillRecurrence.custom && (customIntervalDays == null || customIntervalDays <= 0)) {
      throw const AppException('Custom recurrence needs a repeat interval greater than 0 days');
    }

    final bill = Bill(
      id: IdGenerator.generate(),
      name: name,
      amount: amount,
      dueDate: dueDate,
      recurrence: recurrence,
      accountId: accountId,
      categoryId: categoryId,
      customIntervalDays: recurrence == BillRecurrence.custom ? customIntervalDays : null,
      reminderOffsets: reminderOffsets,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await add(bill.id, bill);
    _scheduleReminders(bill);
    return bill;
  }

  /// [amount]/[dueDate]/[recurrence]/[customIntervalDays] editable
  /// post-creation, unlike e.g. [Account.openingBalance] — a bill's terms
  /// legitimately change (rent increases, due date shifts).
  Future<void> editBill(
    Bill bill, {
    String? name,
    double? amount,
    DateTime? dueDate,
    BillRecurrence? recurrence,
    String? accountId,
    String? categoryId,
    int? customIntervalDays,
    List<int>? reminderOffsets,
    String? notes,
  }) async {
    if (amount != null && amount <= 0) {
      throw const AppException('Bill amount must be greater than 0');
    }
    final effectiveRecurrence = recurrence ?? bill.recurrence;
    final effectiveCustomDays = customIntervalDays ?? bill.customIntervalDays;
    if (effectiveRecurrence == BillRecurrence.custom &&
        (effectiveCustomDays == null || effectiveCustomDays <= 0)) {
      throw const AppException('Custom recurrence needs a repeat interval greater than 0 days');
    }

    bill.updateField(field: 'name', oldValue: bill.name, newValue: name, apply: (v) => bill.name = v);
    bill.updateField(field: 'amount', oldValue: bill.amount, newValue: amount, apply: (v) => bill.amount = v);
    bill.updateField(field: 'dueDate', oldValue: bill.dueDate, newValue: dueDate, apply: (v) => bill.dueDate = v);
    bill.updateField(
      field: 'recurrence',
      oldValue: bill.recurrence,
      newValue: recurrence,
      apply: (v) => bill.recurrence = v,
    );
    bill.updateField(
      field: 'accountId',
      oldValue: bill.accountId,
      newValue: accountId,
      apply: (v) => bill.accountId = v,
    );
    bill.updateField(
      field: 'categoryId',
      oldValue: bill.categoryId,
      newValue: categoryId,
      apply: (v) => bill.categoryId = v,
    );
    bill.updateField(
      field: 'customIntervalDays',
      oldValue: bill.customIntervalDays,
      newValue: customIntervalDays,
      apply: (v) => bill.customIntervalDays = v,
    );
    bill.updateField(
      field: 'notes',
      oldValue: bill.notes,
      newValue: notes,
      apply: (v) => bill.notes = v,
    );
    if (reminderOffsets != null && !_listEquals(bill.reminderOffsets, reminderOffsets)) {
      bill.recordEdit(
        field: 'reminderOffsets',
        oldValue: bill.reminderOffsets.toString(),
        newValue: reminderOffsets.toString(),
      );
      bill.reminderOffsets = reminderOffsets;
    }
    await update(bill);
    _scheduleReminders(bill);
  }

  /// Applies a payment delta toward the current occurrence, clamped so
  /// [Bill.amountPaid] never exceeds [Bill.amount], then rolls the bill
  /// forward to its next occurrence once the delta brings it to full.
  /// Mirrors [PersonRepository.adjustBalance]'s audit pattern.
  Future<void> applyPayment(Bill bill, double delta) async {
    if (delta == 0) return;
    final newAmountPaid = (bill.amountPaid + delta).clamp(0, bill.amount).toDouble();
    bill.recordEdit(
      field: 'amountPaid',
      oldValue: bill.amountPaid.toString(),
      newValue: newAmountPaid.toString(),
    );
    bill.amountPaid = newAmountPaid;

    var rolledOver = false;
    if (newAmountPaid >= bill.amount) {
      _rollOverIfRecurring(bill);
      rolledOver = true;
    }
    await update(bill);
    if (rolledOver) _scheduleReminders(bill);
  }

  /// Marks the current occurrence fully paid without an explicit payment
  /// record — used for "quick mark as paid" without entering an amount.
  Future<void> markPaid(Bill bill) async {
    if (bill.amountPaid >= bill.amount) return;
    bill.recordEdit(
      field: 'amountPaid',
      oldValue: bill.amountPaid.toString(),
      newValue: bill.amount.toString(),
    );
    bill.amountPaid = bill.amount;
    final isRecurring = bill.recurrence != BillRecurrence.oneTime;
    _rollOverIfRecurring(bill);
    await update(bill);
    if (isRecurring) {
      _scheduleReminders(bill);
    } else {
      _cancelReminders(bill.id);
    }
  }

  /// Marks the current occurrence skipped (not paid, not counted as
  /// overdue) and rolls a recurring bill forward.
  Future<void> skipOccurrence(Bill bill) async {
    if (bill.isSkipped) return;
    bill.recordEdit(field: 'isSkipped', oldValue: 'false', newValue: 'true');
    bill.isSkipped = true;
    final isRecurring = bill.recurrence != BillRecurrence.oneTime;
    _rollOverIfRecurring(bill);
    await update(bill);
    if (isRecurring) {
      _scheduleReminders(bill);
    } else {
      _cancelReminders(bill.id);
    }
  }

  Future<void> unskip(Bill bill) async {
    if (!bill.isSkipped) return;
    bill.recordEdit(field: 'isSkipped', oldValue: 'true', newValue: 'false');
    bill.isSkipped = false;
    await update(bill);
    _scheduleReminders(bill);
  }

  /// Advances [Bill.dueDate] to its next occurrence and resets
  /// [Bill.amountPaid]/[Bill.isSkipped] for it. No-ops for [BillRecurrence.oneTime]
  /// — a one-time bill just stays in its final paid/skipped state.
  void _rollOverIfRecurring(Bill bill) {
    if (bill.recurrence == BillRecurrence.oneTime) return;

    final nextDueDate = bill.recurrence.nextDueDate(bill.dueDate, customDays: bill.customIntervalDays);
    bill.recordEdit(field: 'dueDate', oldValue: bill.dueDate.toString(), newValue: nextDueDate.toString());
    bill.dueDate = nextDueDate;
    bill.amountPaid = 0;
    bill.isSkipped = false;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Best-effort, fire-and-forget — a notification scheduling failure
  /// (e.g. plugin not initialized in a test/desktop context) must never
  /// block or fail a Firestore write.
  void _scheduleReminders(Bill bill) {
    ReminderNotificationService.reschedule(
      ownerId: bill.id,
      title: bill.name,
      bodyBuilder: (offset) => '${reminderOffsetLabel(offset)} — due ${bill.dueDate.day}/${bill.dueDate.month}',
      dueDate: bill.dueDate,
      offsets: bill.reminderOffsets,
    ).catchError((_) {});
  }

  void _cancelReminders(String billId) {
    ReminderNotificationService.cancel(billId).catchError((_) {});
  }
}
