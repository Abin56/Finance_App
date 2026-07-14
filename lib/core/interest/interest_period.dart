/// The cadence an interest rate is quoted in, or that installments repeat
/// at — used to normalize a user-quoted rate to a per-installment rate.
enum InterestPeriod { monthly, yearly }

extension InterestPeriodX on InterestPeriod {
  static InterestPeriod fromName(String name) =>
      InterestPeriod.values.firstWhere((p) => p.name == name, orElse: () => InterestPeriod.monthly);

  String get label {
    switch (this) {
      case InterestPeriod.monthly:
        return 'Per Month';
      case InterestPeriod.yearly:
        return 'Per Year';
    }
  }
}
