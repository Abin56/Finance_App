/// How a split [Expense]'s total is divided across its participants.
enum SplitType { equal, custom, percentage, none }

extension SplitTypeX on SplitType {
  static SplitType fromName(String name) =>
      SplitType.values.firstWhere((t) => t.name == name, orElse: () => SplitType.none);

  String get label {
    switch (this) {
      case SplitType.equal:
        return 'Split equally';
      case SplitType.custom:
        return 'Custom amounts';
      case SplitType.percentage:
        return 'Split by percentage';
      case SplitType.none:
        return 'Not split';
    }
  }
}
