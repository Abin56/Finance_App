import '../../../transactions/domain/transaction_type.dart';

/// One remembered conversion decision: "the last time an SMS from this
/// merchant became a [transactionType], the user filed it under
/// [categoryId]". Written only after the receiving screen's own save has
/// genuinely succeeded, so a memory always reflects a real, completed choice
/// the user made — never a suggestion this app made for them.
///
/// Keyed by merchant *and* type because the same merchant legitimately
/// appears on both sides of the ledger (an Amazon purchase vs an Amazon
/// refund), and those belong in different categories.
///
/// Stored only in the local `sms_inbox.db` (never Firestore), same privacy
/// boundary as the inbox rows themselves — see `SmsInboxRepository`.
class MerchantMemory {
  const MerchantMemory({
    required this.merchantKey,
    required this.transactionType,
    required this.categoryId,
    required this.timesUsed,
    required this.lastUsedAt,
  });

  /// A `MerchantKey.normalize`d merchant string — never the raw SMS text.
  final String merchantKey;
  final TransactionType transactionType;
  final String categoryId;

  /// How many times the user has filed this merchant under [categoryId].
  /// Drives which memory wins when the user has genuinely changed their mind
  /// over time — see `MerchantCategorySuggester`.
  final int timesUsed;
  final DateTime lastUsedAt;
}
