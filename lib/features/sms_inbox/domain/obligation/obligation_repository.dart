import 'financial_obligation.dart';
import 'obligation_link.dart';
import 'obligation_linker.dart';
import 'obligation_status.dart';

/// An in-memory [FinancialObligation] store implementing [ObligationLookup]
/// — a foundation-phase stand-in for real persistence.
///
/// Deliberately not backed by `SmsInboxDatabase`/sqflite in this phase:
/// that migration chain (`schemaVersion`, `onUpgrade`) is actively owned by
/// the parallel Phase 2/3 session, and adding an `obligations` table there
/// risks a schema-version collision. Wiring a real `ObligationDao` (mirror
/// of `FinancialEventDao`'s thin-CRUD-only pattern, see its doc comment)
/// into that migration chain is the integration point a future session
/// should pick up — this class's [ObligationLookup] surface is the
/// contract that DAO would need to satisfy.
class InMemoryObligationRepository implements ObligationLookup {
  final Map<String, FinancialObligation> _byId = {};

  Future<void> upsert(FinancialObligation obligation) async {
    _byId[obligation.id] = obligation;
  }

  Future<FinancialObligation?> getById(String id) async => _byId[id];

  Future<List<FinancialObligation>> getAll() async =>
      List.unmodifiable(_byId.values);

  Future<List<FinancialObligation>> getOutstanding() async =>
      _byId.values.where((o) => o.status.isOutstanding).toList(growable: false);

  /// Marks [id] resolved by [linkedEventId] — the one place this repository
  /// mutates an obligation's [ObligationStatus.completed] state, and only
  /// ever called with an already-decided [ObligationLinkOutcome] from
  /// [ObligationLinker], never inferred here.
  Future<FinancialObligation> markResolved({
    required String id,
    required String linkedEventId,
    required DateTime resolvedAt,
  }) async {
    final existing = _byId[id];
    if (existing == null) {
      throw StateError('No obligation with id "$id" found.');
    }
    final resolved = existing.copyWith(
      status: ObligationStatus.completed,
      linkedEventId: linkedEventId,
      updatedAt: resolvedAt,
    );
    _byId[id] = resolved;
    return resolved;
  }

  @override
  Future<FinancialObligation?> findOutstandingByReferenceNumber(
    String referenceNumber,
  ) async {
    for (final obligation in _byId.values) {
      if (obligation.status.isOutstanding &&
          obligation.referenceNumber == referenceNumber) {
        return obligation;
      }
    }
    return null;
  }

  @override
  Future<List<FinancialObligation>> findOutstandingByMerchant({
    required String? merchantOrSender,
    required DateTime anchorDate,
    required Duration lookback,
  }) async {
    if (merchantOrSender == null || merchantOrSender.isEmpty) return const [];
    final needle = merchantOrSender.toLowerCase();
    final windowStart = anchorDate.subtract(lookback);

    return _byId.values
        .where((o) {
          if (!o.status.isOutstanding) return false;
          final merchant = o.merchant.value?.toLowerCase();
          final merchantOverlaps =
              merchant != null &&
              (merchant.contains(needle) || needle.contains(merchant));
          if (!merchantOverlaps) return false;

          final due = o.dueDate.value;
          if (due != null) {
            return !due.isBefore(windowStart) && !due.isAfter(anchorDate);
          }
          // No resolved due date — fall back to when the obligation was first
          // detected, so a reminder with an unresolved date can still be
          // linked.
          return !o.createdAt.isBefore(windowStart) &&
              !o.createdAt.isAfter(anchorDate);
        })
        .toList(growable: false);
  }
}
