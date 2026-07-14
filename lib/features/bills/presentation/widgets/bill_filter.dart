import '../../domain/bill_status.dart';

/// Immutable filter selection applied on top of the live bills stream —
/// kept entirely client-side, same rationale as `TransactionFilter`.
class BillFilter {
  const BillFilter({this.status, this.categoryId, this.accountId, this.startDate, this.endDate});

  final BillStatus? status;
  final String? categoryId;
  final String? accountId;
  final DateTime? startDate;
  final DateTime? endDate;

  bool get isActive =>
      status != null || categoryId != null || accountId != null || startDate != null || endDate != null;
}
