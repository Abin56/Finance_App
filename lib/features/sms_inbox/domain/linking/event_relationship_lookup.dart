import '../financial_event/financial_event.dart';

/// The read-only query surface [EventRelationshipEngine] needs against the
/// pool of already-known `FinancialEvent`s — kept as an interface (mirrors
/// Phase 4's `ObligationLookup`) so a real `FinancialEventDao`-backed
/// implementation can be swapped in later without the engine changing. See
/// [InMemoryEventRelationshipRepository] for this phase's foundation-only
/// implementation.
abstract class EventRelationshipLookup {
  /// Events whose own `referenceNumber` normalizes to the same value as
  /// [referenceNumber] — mirrors `FinancialEventDao.findByReferenceNumber`.
  Future<List<FinancialEvent>> findByReferenceNumber(String referenceNumber);

  /// Events from the same normalized sender with the same amount, within
  /// `[start, end]` — mirrors `FinancialEventDao.findBySenderAmountWindow`.
  Future<List<FinancialEvent>> findBySenderAmountWindow({
    required String? normalizedSender,
    required double? amount,
    required DateTime start,
    required DateTime end,
  });

  /// Events whose resolved merchant normalizes to the same value as
  /// [merchant], within `[start, end]` — a signal `FinancialEventDao` does
  /// not currently expose a dedicated query for.
  Future<List<FinancialEvent>> findByMerchantWindow({
    required String? merchant,
    required DateTime start,
    required DateTime end,
  });

  /// Events with the same [amount], within `[start, end]` — the broadest
  /// prefilter, needed so a pair that only shares a non-amount hard signal
  /// (same account, same card) with no merchant/sender/reference still
  /// enters the candidate pool at all; [EventRelationshipEngine]'s own
  /// scoring (never amount alone) is what keeps this safe.
  Future<List<FinancialEvent>> findByAmountWindow({
    required double? amount,
    required DateTime start,
    required DateTime end,
  });

  /// Own-account-transfer-flagged events with the given [amount], within
  /// `[start, end]`, excluding [excludeEventId] itself — the candidate pool
  /// [TransferPairDetector] searches for the opposite leg of a transfer.
  Future<List<FinancialEvent>> findOwnAccountTransferCandidates({
    required double amount,
    required DateTime start,
    required DateTime end,
    required String excludeEventId,
  });
}
