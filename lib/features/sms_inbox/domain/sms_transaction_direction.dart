/// Whether a parsed SMS transaction moved money out of ([debit]) or into
/// ([credit]) the user's account. Mirrors `TransactionType.expense`/`.income`
/// in spirit, but is kept as its own enum since a parsed SMS is not yet a
/// real `Transaction` — only converting it creates one.
enum SmsTransactionDirection { debit, credit }

extension SmsTransactionDirectionX on SmsTransactionDirection {
  static SmsTransactionDirection? fromName(String? name) {
    if (name == null) return null;
    for (final d in SmsTransactionDirection.values) {
      if (d.name == name) return d;
    }
    return null;
  }

  String get label {
    switch (this) {
      case SmsTransactionDirection.debit:
        return 'Debit';
      case SmsTransactionDirection.credit:
        return 'Credit';
    }
  }
}
