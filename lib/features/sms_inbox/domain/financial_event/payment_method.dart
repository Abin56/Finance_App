/// How the money moved — a separate concept from which [FinancialEventType]
/// the event is (a payment can be UPI or a debit card; a receipt can be UPI
/// or a bank transfer). Doubles as this feature's "transaction channel"
/// concept (see the Phase 5 SMS rebuild plan's Part 6) — deliberately not a
/// second, parallel enum: [PaymentMethod] already distinguishes UPI/card/
/// net-banking/NEFT-RTGS-IMPS/cash/wallet, which is the same question
/// "transaction channel" asks. [atm] is the one gap this phase closes: an
/// ATM withdrawal is more specific than plain [cash] (it's cash *dispensed
/// by a machine*, not a bank-counter/cash-deposit event), and conflating
/// the two would lose that distinction. [merchant]/[paymentProvider]
/// (`FinancialEvent`'s own fields) stay entirely separate concepts — the
/// channel a payment travelled on never implies who was paid or which app
/// initiated it.
enum PaymentMethod {
  upi,
  debitCard,
  creditCard,
  netBanking,
  neftRtgsImps,
  cash,
  wallet,
  atm,
  unknown,
}

extension PaymentMethodX on PaymentMethod {
  static PaymentMethod fromName(String? name) {
    if (name == null) return PaymentMethod.unknown;
    return PaymentMethod.values.firstWhere(
      (m) => m.name == name,
      orElse: () => PaymentMethod.unknown,
    );
  }

  String get label {
    switch (this) {
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.debitCard:
        return 'Debit card';
      case PaymentMethod.creditCard:
        return 'Credit card';
      case PaymentMethod.netBanking:
        return 'Net banking';
      case PaymentMethod.neftRtgsImps:
        return 'NEFT / RTGS / IMPS';
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.wallet:
        return 'Wallet';
      case PaymentMethod.atm:
        return 'ATM';
      case PaymentMethod.unknown:
        return 'Unknown';
    }
  }
}
