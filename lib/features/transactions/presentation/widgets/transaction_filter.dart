import '../../domain/transaction_type.dart';

/// Sort order applied to the History list, chosen via the AppBar sort menu.
enum TransactionSort { dateDesc, dateAsc, amountDesc, amountAsc }

extension TransactionSortX on TransactionSort {
  String get label {
    switch (this) {
      case TransactionSort.dateDesc:
        return 'Newest first';
      case TransactionSort.dateAsc:
        return 'Oldest first';
      case TransactionSort.amountDesc:
        return 'Highest amount';
      case TransactionSort.amountAsc:
        return 'Lowest amount';
    }
  }
}

/// Immutable filter selection applied on top of the live transaction
/// stream — kept entirely client-side (see [TransactionsScreen]) since a
/// personal-finance transaction volume doesn't warrant composite Firestore
/// indexes for every filter combination.
class TransactionFilter {
  const TransactionFilter({
    this.type,
    this.accountId,
    this.categoryId,
    this.startDate,
    this.endDate,
    this.includeExcluded = true,
    this.filterByAccountingMonth = false,
  });

  final TransactionType? type;
  final String? accountId;
  final String? categoryId;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Whether `excludeFromCalculations` transactions show up at all — true
  /// by default so a fresh filter behaves like no filter was applied. Set
  /// false to hide them, or combine with a date range to view only excluded
  /// transactions (see `TransactionFilterSheet`'s "excluded only" toggle).
  final bool includeExcluded;

  /// Whether [startDate]/[endDate] match against a transaction's Accounting
  /// Month instead of its real date.
  final bool filterByAccountingMonth;

  bool get isActive =>
      type != null ||
      accountId != null ||
      categoryId != null ||
      startDate != null ||
      endDate != null ||
      !includeExcluded ||
      filterByAccountingMonth;

  TransactionFilter copyWith({
    TransactionType? type,
    bool clearType = false,
    String? accountId,
    bool clearAccountId = false,
    String? categoryId,
    bool clearCategoryId = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
    bool? includeExcluded,
    bool? filterByAccountingMonth,
  }) {
    return TransactionFilter(
      type: clearType ? null : (type ?? this.type),
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      includeExcluded: includeExcluded ?? this.includeExcluded,
      filterByAccountingMonth: filterByAccountingMonth ?? this.filterByAccountingMonth,
    );
  }
}
