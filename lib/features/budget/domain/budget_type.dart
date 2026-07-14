/// Whether a [Budget] tracks spending for a single day or a full month.
/// Category budgets reuse [monthly] — the spec's examples (Food ₹10,000,
/// Travel ₹5,000) are monthly limits, so a third enum value would just
/// duplicate this one.
enum BudgetType { daily, monthly }

extension BudgetTypeX on BudgetType {
  static BudgetType fromName(String name) =>
      BudgetType.values.firstWhere((t) => t.name == name, orElse: () => BudgetType.monthly);

  String get label {
    switch (this) {
      case BudgetType.daily:
        return 'Daily';
      case BudgetType.monthly:
        return 'Monthly';
    }
  }
}
