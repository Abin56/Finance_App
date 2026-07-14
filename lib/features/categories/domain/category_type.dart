import '../../transactions/domain/transaction_type.dart';

/// Whether a category applies to income transactions, expense transactions,
/// or both (e.g. "Other" / "Transfer" can be used either way).
enum CategoryType { income, expense, both }

extension CategoryTypeX on CategoryType {
  static CategoryType fromName(String name) =>
      CategoryType.values.firstWhere((t) => t.name == name, orElse: () => CategoryType.both);

  String get label {
    switch (this) {
      case CategoryType.income:
        return 'Income';
      case CategoryType.expense:
        return 'Expense';
      case CategoryType.both:
        return 'Income & Expense';
    }
  }

  /// Whether a category of this type should be offered when the user is
  /// adding a transaction of [transactionType].
  bool appliesTo(TransactionType transactionType) {
    switch (this) {
      case CategoryType.income:
        return transactionType == TransactionType.income;
      case CategoryType.expense:
        return transactionType == TransactionType.expense;
      case CategoryType.both:
        return true;
    }
  }
}
