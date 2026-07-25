import 'cycle_item.dart';
import 'cycle_source_type.dart';
import 'installment.dart';
import 'installment_status.dart';
import 'owner_type.dart';

/// Adapts an [Installment] to [CycleItem] so EMI/Loan schedules can run
/// through [CycleEngine] without any change to [Installment] or
/// `InstallmentRepository` themselves.
class InstallmentCycleItem extends CycleItem {
  const InstallmentCycleItem(this.installment);

  final Installment installment;

  @override
  String get id => installment.id;

  @override
  CycleSourceType get sourceType {
    switch (installment.ownerType) {
      case OwnerType.loan:
        return CycleSourceType.loan;
      case OwnerType.emi:
        return CycleSourceType.emi;
      case OwnerType.splitExpense:
        return CycleSourceType.splitExpense;
      case OwnerType.bill:
        return CycleSourceType.bill;
    }
  }

  @override
  String get sourceId => installment.id;

  @override
  DateTime get cycleDate => installment.dueDate;

  @override
  double? get totalAmount => installment.amountDue;

  @override
  double? get paidAmount => installment.amountPaid;

  @override
  bool get isSettled =>
      installment.status == InstallmentStatus.paid || installment.status == InstallmentStatus.skipped;

  @override
  bool get isOverdue => installment.status == InstallmentStatus.overdue;
}
