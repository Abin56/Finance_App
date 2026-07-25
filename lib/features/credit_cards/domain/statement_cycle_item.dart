import '../../../core/payment_schedule/domain/cycle_item.dart';
import '../../../core/payment_schedule/domain/cycle_source_type.dart';
import 'statement.dart';
import 'statement_status.dart';

/// Adapts a [Statement] to [CycleItem] so the shared cycle engine can
/// carry-forward pending statements without knowing what a Statement is.
/// Purely a view — never persisted, constructed fresh from an
/// already-loaded [Statement] on every read.
class StatementCycleItem extends CycleItem {
  const StatementCycleItem(this.statement);

  final Statement statement;

  @override
  String get id => statement.id;

  @override
  CycleSourceType get sourceType => CycleSourceType.creditCardStatement;

  @override
  String get sourceId => statement.id;

  @override
  DateTime get cycleDate => statement.periodEnd;

  @override
  double? get totalAmount => statement.totalAmount;

  @override
  double? get paidAmount => statement.amountPaid;

  @override
  bool get isSettled => statement.remainingAmount <= 0;

  @override
  bool get isOverdue => statement.status == StatementStatus.overdue;
}
