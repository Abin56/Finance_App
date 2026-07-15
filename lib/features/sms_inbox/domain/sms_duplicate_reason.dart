/// Why an incoming SMS was judged a duplicate of one already stored.
///
/// Recorded per row and shown verbatim in the Duplicates filter, because
/// "we hid this" is not an acceptable explanation for making one of a user's
/// messages disappear — they get to see the rule that fired and overrule it.
enum SmsDuplicateReason {
  /// Same normalized sender, timestamp and amount, and the same bank
  /// reference/transaction number. The strongest signal there is: a bank
  /// re-sending one payment (different DLT sender prefix, or different
  /// trailing promo text) reuses the reference number.
  sameReferenceNumber,

  /// Same normalized sender, timestamp and amount, with no reference number
  /// on either message to confirm with — the bodies differed only in text the
  /// dedup key ignores.
  sameSenderAmountAndTime,
}

extension SmsDuplicateReasonX on SmsDuplicateReason {
  static SmsDuplicateReason fromName(String? name) {
    return SmsDuplicateReason.values.firstWhere(
      (reason) => reason.name == name,
      orElse: () => SmsDuplicateReason.sameSenderAmountAndTime,
    );
  }

  /// Written for the person reviewing the pair, not for a log — it has to
  /// justify the call well enough for them to accept or reject it.
  String get explanation {
    switch (this) {
      case SmsDuplicateReason.sameReferenceNumber:
        return 'Same bank reference number, amount and time as the original.';
      case SmsDuplicateReason.sameSenderAmountAndTime:
        return 'Same sender, amount and time as the original.';
    }
  }
}
