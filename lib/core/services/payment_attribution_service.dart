import '../../features/people/data/ledger_repository.dart';
import '../../features/people/domain/ledger_entry_type.dart';
import '../errors/app_exception.dart';
import '../models/payer_source.dart';
import '../utils/currency_formatter.dart';

/// One payment to apply toward one obligation (an EMI/Loan installment, a
/// Bill, a split expense participant's share, or any future payable
/// module) — [record] is the existing repository call that actually applies
/// it (e.g. `(amount, date, note) => installmentPaymentRepository.recordPayment(installment, amount: amount, date: date, note: note)`),
/// so [PaymentAttributionService] never re-implements "apply a delta and
/// keep the cached total in sync" for any module — that logic already
/// lives in `InstallmentPaymentRepository`/`PaymentRepository`/etc., and
/// stays there.
class PaymentAttributionItem {
  const PaymentAttributionItem({
    required this.obligationLabel,
    required this.amount,
    required this.record,
  });

  /// Plain-language name of what this payment is for — e.g. "your Bike
  /// EMI", "your Electricity bill", "Rahul's loan installment" — used to
  /// build the history sentence. Written from the account owner's point of
  /// view, matching how [PaymentAttributionService.describe] reads.
  final String obligationLabel;

  final double amount;

  /// Applies [amount] toward this obligation via whatever repository
  /// already owns that obligation's payment tracking. Any [AppException]
  /// this throws propagates before any Person ledger entry is posted for
  /// items after it in the batch — see [PaymentAttributionService.apply].
  final Future<void> Function({required double amount, required DateTime date, required String note}) record;
}

/// Records one or more payments against your obligations on someone else's
/// behalf — the reusable "who actually paid this" layer every payable
/// module (EMI, Loan, Bill, Split Expense, and future ones like
/// Investments/Insurance) shares instead of hand-rolling its own "paid by
/// another person" handling. No payment math lives here: each
/// [PaymentAttributionItem.record] delegates to the module's own existing
/// repository (`InstallmentPaymentRepository.recordPayment`,
/// `PaymentRepository.recordPayment`, ...), so this service only adds two
/// things on top of what already exists:
///
///  1. When [payer] is a tracked [Person] (not [PayerSource.self]): posts
///     *one* `LedgerEntry` for the batch's total — "they paid this, so you
///     now owe them" (`LedgerEntryType.borrowed`) — instead of one entry
///     per installment, so a "paid multiple installments together" batch
///     shows as a single clean ledger line.
///  2. A plain-language history sentence per item (e.g. "Rahul paid ₹5,000
///     towards your Bike EMI") via [describe], for history/timeline UIs to
///     render without ever seeing "installment"/"schedule"/"ledger".
class PaymentAttributionService {
  const PaymentAttributionService({required this.ledgerRepositoryFor});

  /// Resolves a `LedgerRepository` scoped to a given person id — supplied
  /// by the provider layer, same shape `ReceiptClassificationRouter` uses.
  final LedgerRepository Function(String personId) ledgerRepositoryFor;

  /// Applies every item in [items] (in order) and, if [payer] is a
  /// [PersonPayerSource], posts one combined `LedgerEntry` for their total.
  /// Returns a plain-language history sentence per item, in the same
  /// order, via [describe] — callers append these to whatever history/audit
  /// surface they render.
  Future<List<String>> apply({
    required List<PaymentAttributionItem> items,
    required PayerSource payer,
    required DateTime date,
    String note = '',
  }) async {
    if (items.isEmpty) {
      throw const AppException('At least one payment is required');
    }
    for (final item in items) {
      if (item.amount <= 0) {
        throw const AppException('Each payment amount must be greater than 0');
      }
    }

    for (final item in items) {
      await item.record(amount: item.amount, date: date, note: note);
    }

    if (payer case PersonPayerSource(:final person)) {
      final total = items.fold(0.0, (sum, item) => sum + item.amount);
      await ledgerRepositoryFor(person.id).addEntry(
        person,
        type: LedgerEntryType.borrowed,
        amount: total,
        date: date,
        note: note.isEmpty ? _batchNote(items) : note,
      );
    }

    return [for (final item in items) describe(payer: payer, item: item)];
  }

  /// "Rahul paid ₹5,000 towards your Bike EMI" / "You paid ₹5,000 towards
  /// your Bike EMI" — the plain-language line history/timeline UIs show,
  /// so no feature has to build its own wording for "who paid what".
  String describe({required PayerSource payer, required PaymentAttributionItem item}) {
    final payerName = switch (payer) {
      SelfPayerSource() => 'You',
      PersonPayerSource(:final person) => person.name,
    };
    return '$payerName paid ${CurrencyFormatter.instance.format(item.amount)} towards ${item.obligationLabel}';
  }

  String _batchNote(List<PaymentAttributionItem> items) {
    if (items.length == 1) return 'Paid towards ${items.first.obligationLabel}';
    return 'Paid towards ${items.length} payments';
  }
}
