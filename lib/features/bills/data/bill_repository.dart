import '../../../core/data/firestore_crud_repository.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/bill.dart';
import '../domain/bill_recurrence.dart';

/// Bill-template persistence on top of the generic CRUD/soft-delete
/// repository — create/edit the recurring rule itself. Occurrence
/// materialization, payments, and rollover live in
/// `BillOccurrenceRepository`; reminders are scheduled per-occurrence
/// there too, since each occurrence needs its own independently
/// cancellable notification.
class BillRepository extends FirestoreCrudRepository<Bill> {
  BillRepository(super.collection);

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
      nextDueDate: dueDate,
      recurrence: recurrence,
      accountId: accountId,
      categoryId: categoryId,
      customIntervalDays: recurrence == BillRecurrence.custom ? customIntervalDays : null,
      reminderOffsets: reminderOffsets,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await add(bill.id, bill);
    return bill;
  }

  /// [amount]/[nextDueDate]/[recurrence]/[customIntervalDays] editable
  /// post-creation, unlike e.g. [Account.openingBalance] — a bill's terms
  /// legitimately change (rent increases, due date shifts). Never touches
  /// an already-materialized [BillOccurrence] — editing the template only
  /// affects occurrences generated after this call.
  Future<void> editBill(
    Bill bill, {
    String? name,
    double? amount,
    DateTime? nextDueDate,
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
    bill.updateField(
      field: 'nextDueDate',
      oldValue: bill.nextDueDate,
      newValue: nextDueDate,
      apply: (v) => bill.nextDueDate = v,
    );
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
  }

  /// Advances [Bill.nextDueDate] to [next] — called by
  /// `BillOccurrenceRepository` immediately after materializing a new
  /// occurrence at the template's current `nextDueDate`, the same way
  /// `StatementRepository` never mutates `CreditCardProfile.statementDay`
  /// itself but a card's "current cycle" is always derived from it fresh.
  Future<void> advanceNextDueDate(Bill bill, DateTime next) async {
    bill.recordEdit(field: 'nextDueDate', oldValue: bill.nextDueDate.toString(), newValue: next.toString());
    bill.nextDueDate = next;
    await update(bill);
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
