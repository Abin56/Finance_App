import '../../transactions/domain/transaction_type.dart';
import '../domain/merchant/merchant_key.dart';
import '../domain/merchant/merchant_memory.dart';
import 'merchant_memory_dao.dart';

/// The merchant-memory feature's API surface, and the single place raw
/// merchant text is turned into a `MerchantKey`. Callers pass the merchant
/// string straight off the SMS and never normalize it themselves — that is
/// what guarantees the key written on `record` is the same shape the
/// suggester later looks up.
///
/// Like [SmsInboxRepository], this depends only on local sqflite and imports
/// nothing Firestore-related: a merchant memory is derived from on-device SMS
/// and stays on-device.
class MerchantMemoryRepository {
  const MerchantMemoryRepository(this._dao);

  final MerchantMemoryDao _dao;

  Future<List<MerchantMemory>> getAll() => _dao.getAll();

  /// Remembers that [merchant] was filed under [categoryId]. Callers must
  /// only invoke this *after* the receiving screen's own save has genuinely
  /// succeeded — a memory should reflect a transaction the user actually
  /// created, not one they abandoned mid-sheet.
  ///
  /// A no-op when the merchant normalizes to nothing: an empty key would
  /// collide every unidentifiable merchant into one bucket that then recalls
  /// an unrelated category for all of them.
  Future<void> record({
    required String? merchant,
    required TransactionType transactionType,
    required String categoryId,
  }) async {
    final merchantKey = MerchantKey.normalize(merchant);
    if (merchantKey == null) return;

    await _dao.record(
      merchantKey: merchantKey,
      transactionType: transactionType,
      categoryId: categoryId,
      at: DateTime.now(),
    );
  }
}
