import '../financial_event/financial_event.dart';
import '../merchant/merchant_key.dart';
import 'event_relationship.dart';
import 'event_relationship_lookup.dart';
import 'reference_normalizer.dart';

/// An in-memory [FinancialEvent] pool plus a relationship-edge store,
/// implementing [EventRelationshipLookup] — a foundation-phase stand-in for
/// real persistence.
///
/// Deliberately not backed by `SmsInboxDatabase`/`FinancialEventDao` in
/// this phase, for the same reason `InMemoryObligationRepository` (Phase 4)
/// isn't: that migration chain and DAO are actively owned by the parallel
/// Phase 2/3 session, and this phase's job is the matching/relationship
/// *logic*, not a schema change made under someone else's active work. A
/// real `EventRelationshipDao` (mirroring `FinancialEventDao`'s
/// thin-CRUD-only pattern) wired into a new migration is the integration
/// point a future session should pick up — see the deliverable's
/// "Database changes/migrations" section for the exact schema this class's
/// [EventRelationshipLookup] surface implies.
///
/// The `FinancialEvent` remains the anchor, exactly as the existing
/// `financial_events`/`sms_financial_event_links` design already
/// establishes (Part 19): this store's `EventRelationship` rows are edges
/// referencing event/obligation ids, never a replacement identity for an
/// event, and deleting a relationship row here never deletes the
/// `FinancialEvent` it points at (mirroring
/// `FinancialEventDao.deleteLinksForSmsIds`'s documented invariant).
class InMemoryEventRelationshipRepository implements EventRelationshipLookup {
  final Map<String, FinancialEvent> _events = {};
  final List<EventRelationship> _relationships = [];

  void addEvent(FinancialEvent event) => _events[event.id] = event;

  FinancialEvent? getEvent(String id) => _events[id];

  List<EventRelationship> get relationships => List.unmodifiable(_relationships);

  void recordRelationship(EventRelationship relationship) {
    _relationships.add(relationship);
  }

  /// Every relationship edge touching [eventId], as either source or
  /// target — the local neighborhood of the Part 16 event graph.
  List<EventRelationship> relationshipsFor(String eventId) {
    return _relationships
        .where((r) => r.sourceEventId == eventId || r.targetEventId == eventId)
        .toList(growable: false);
  }

  /// Removing a relationship edge never removes the `FinancialEvent`s it
  /// referenced — mirrors `FinancialEventDao.deleteLinksForSmsIds`'s
  /// documented orphan-safety invariant (Part 19/Part 18 item 15).
  void removeRelationship(String relationshipId) {
    _relationships.removeWhere((r) => r.id == relationshipId);
  }

  @override
  Future<List<FinancialEvent>> findByReferenceNumber(
    String referenceNumber,
  ) async {
    final normalized = ReferenceNormalizer.normalize(referenceNumber);
    if (normalized == null) return const [];
    return _events.values
        .where(
          (e) => ReferenceNormalizer.normalize(e.referenceNumber) == normalized,
        )
        .toList(growable: false);
  }

  @override
  Future<List<FinancialEvent>> findBySenderAmountWindow({
    required String? normalizedSender,
    required double? amount,
    required DateTime start,
    required DateTime end,
  }) async {
    if (normalizedSender == null || amount == null) return const [];
    return _events.values
        .where(
          (e) =>
              e.normalizedSender == normalizedSender &&
              e.amount.value != null &&
              (e.amount.value! - amount).abs() < 0.01 &&
              !e.eventDate.isBefore(start) &&
              !e.eventDate.isAfter(end),
        )
        .toList(growable: false);
  }

  @override
  Future<List<FinancialEvent>> findByMerchantWindow({
    required String? merchant,
    required DateTime start,
    required DateTime end,
  }) async {
    final normalized = MerchantKey.normalize(merchant);
    if (normalized == null) return const [];
    return _events.values
        .where(
          (e) =>
              MerchantKey.normalize(e.merchant.value) == normalized &&
              !e.eventDate.isBefore(start) &&
              !e.eventDate.isAfter(end),
        )
        .toList(growable: false);
  }

  @override
  Future<List<FinancialEvent>> findByAmountWindow({
    required double? amount,
    required DateTime start,
    required DateTime end,
  }) async {
    if (amount == null) return const [];
    return _events.values
        .where(
          (e) =>
              e.amount.value != null &&
              (e.amount.value! - amount).abs() < 0.01 &&
              !e.eventDate.isBefore(start) &&
              !e.eventDate.isAfter(end),
        )
        .toList(growable: false);
  }

  @override
  Future<List<FinancialEvent>> findOwnAccountTransferCandidates({
    required double amount,
    required DateTime start,
    required DateTime end,
    required String excludeEventId,
  }) async {
    return _events.values
        .where(
          (e) =>
              e.id != excludeEventId &&
              e.isOwnAccountTransfer &&
              e.amount.value != null &&
              (e.amount.value! - amount).abs() < 0.01 &&
              !e.eventDate.isBefore(start) &&
              !e.eventDate.isAfter(end),
        )
        .toList(growable: false);
  }
}
