import '../../../core/payment_schedule/domain/cycle_item.dart';
import '../../../core/payment_schedule/domain/cycle_source_type.dart';
import 'bill_occurrence.dart';
import 'bill_status.dart';

/// Adapts a [BillOccurrence] to [CycleItem] so the shared cycle engine can
/// carry-forward pending bill occurrences the same way `StatementCycleItem`
/// (Credit Cards) does. Purely a view — never persisted, constructed fresh
/// from an already-loaded [BillOccurrence] on every read. Unlike the
/// now-removed `BillCycleItem` (which wrapped the whole mutable `Bill` and
/// could only ever reflect one rolled-over document's current state), each
/// [BillOccurrence] is its own immutable-once-settled document, so
/// `CycleEngine.classifyForCarryForward` run over a bill's occurrences
/// produces real previous/current/future classification.
class BillOccurrenceCycleItem extends CycleItem {
  const BillOccurrenceCycleItem(this.occurrence);

  final BillOccurrence occurrence;

  @override
  String get id => occurrence.id;

  @override
  CycleSourceType get sourceType => CycleSourceType.bill;

  /// The template this occurrence belongs to — not [id] itself, since a
  /// tap on a carried-forward row should route to the bill's own detail
  /// screen, not a document that has no screen of its own.
  @override
  String get sourceId => occurrence.billId;

  @override
  DateTime get cycleDate => occurrence.dueDate;

  @override
  double? get totalAmount => occurrence.amount;

  @override
  double? get paidAmount => occurrence.amountPaid;

  @override
  bool get isSettled => occurrence.status == BillStatus.paid || occurrence.status == BillStatus.skipped;

  @override
  bool get isOverdue => occurrence.status == BillStatus.overdue;
}
