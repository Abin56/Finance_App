import '../../features/people/domain/person.dart';

/// Who actually handed over the money for a payment recorded against *your*
/// obligation (an EMI installment, a Loan installment, a Bill, a split
/// expense's own settlement, or any future payable module) — as opposed to
/// [ReceiptPurpose], which classifies money *you* received. A [PayerSource]
/// answers "who paid this on my behalf", independent of what was paid.
///
/// [PaymentAttributionService] is the only place that reads this — adding a
/// new source (e.g. `splitExpenseParticipant`) means adding one case here
/// and one branch there, not touching every payable module.
sealed class PayerSource {
  const PayerSource();

  /// You paid it yourself — the common case, and the default when no
  /// [PayerSource] is supplied. No Person ledger effect.
  const factory PayerSource.self() = SelfPayerSource;

  /// A tracked [Person] paid on your behalf — you now owe them this amount
  /// (see [PaymentAttributionService], which posts a `LedgerEntryType.borrowed`
  /// entry: they effectively lent you the payment amount).
  const factory PayerSource.person(Person person) = PersonPayerSource;
}

class SelfPayerSource extends PayerSource {
  const SelfPayerSource();
}

class PersonPayerSource extends PayerSource {
  const PersonPayerSource(this.person);

  final Person person;
}
