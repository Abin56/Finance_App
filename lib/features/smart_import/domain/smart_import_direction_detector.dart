import '../../transactions/domain/transaction_type.dart';

/// Reads explicit debit/credit wording out of a screenshot row so a
/// [TransactionType] can be assigned without guessing. Returns null — never
/// a default — when the text has no debit/credit signal at all; the caller
/// is expected to leave the transaction's type unset and flag it for review
/// rather than pick a direction that isn't actually supported by the text.
abstract class SmartImportDirectionDetector {
  SmartImportDirectionDetector._();

  static final RegExp _creditPattern = RegExp(
    r'\b(cr|credit(?:ed)?|received|refund(?:ed)?|cashback|deposit(?:ed)?)\b',
    caseSensitive: false,
  );

  static final RegExp _debitPattern = RegExp(
    r'\b(dr|debit(?:ed)?|paid|spent|purchase(?:d)?|sent|withdrawn|withdrawal)\b',
    caseSensitive: false,
  );

  static TransactionType? detect(String text) {
    final creditMatch = _creditPattern.hasMatch(text);
    final debitMatch = _debitPattern.hasMatch(text);
    if (creditMatch && !debitMatch) return TransactionType.income;
    if (debitMatch && !creditMatch) return TransactionType.expense;
    if (creditMatch && debitMatch) {
      // Both matched (rare) — trust whichever keyword appears first.
      final creditIndex = _creditPattern.firstMatch(text)!.start;
      final debitIndex = _debitPattern.firstMatch(text)!.start;
      return creditIndex < debitIndex
          ? TransactionType.income
          : TransactionType.expense;
    }
    return null;
  }
}
