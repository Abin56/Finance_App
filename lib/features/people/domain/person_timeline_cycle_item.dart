import '../../../core/payment_schedule/domain/cycle_item.dart';
import '../../../core/payment_schedule/domain/cycle_source_type.dart';
import 'person_timeline_entry.dart';

/// Adapts a [PersonTimelineEntry] to [CycleItem] so a person's expense-linked
/// history can run through the shared [CycleEngine] for Previous/Current
/// Cycle carry-forward, the same way Credit Card statements and EMI/Loan
/// installments already do.
///
/// Only [PersonTimelineCategory.assignedExpense]/[PersonTimelineCategory.splitExpense]
/// entries have a real settlement lifecycle (backed by an [Installment] via
/// [PersonTimelineEntry.status]) — every other category (manual lending,
/// manual settlements, adjustments, plain references) is a running-balance
/// movement with no objective "is this outstanding" answer, so callers must
/// filter to those two categories before wrapping entries here (see
/// `personCycleViewProvider`).
class PersonTimelineCycleItem extends CycleItem {
  const PersonTimelineCycleItem(this.entry);

  final PersonTimelineEntry entry;

  @override
  String get id => entry.id;

  @override
  CycleSourceType get sourceType => CycleSourceType.splitExpense;

  @override
  String get sourceId => entry.id;

  @override
  DateTime get cycleDate => entry.date;

  @override
  double? get totalAmount => entry.totalAmount ?? entry.displayAmount.abs();

  @override
  double? get paidAmount => entry.paidAmount ?? (isSettled ? totalAmount : 0);

  @override
  bool get isSettled => entry.status == PersonTimelineStatus.completed;

  @override
  bool get isOverdue => entry.status == PersonTimelineStatus.overdue;
}
