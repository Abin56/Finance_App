/// How interest is calculated over a loan/borrowing's installments.
enum InterestType { flat, reducingBalance }

extension InterestTypeX on InterestType {
  static InterestType fromName(String name) =>
      InterestType.values.firstWhere((t) => t.name == name, orElse: () => InterestType.flat);

  String get label {
    switch (this) {
      case InterestType.flat:
        return 'Flat Interest';
      case InterestType.reducingBalance:
        return 'Reducing Balance';
    }
  }
}
