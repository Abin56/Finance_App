import '../financial_event/financial_event.dart';
import 'event_relationship.dart';
import 'event_relationship_engine.dart';
import 'obligation_settlement_bridge.dart';
import 'transfer_pair_detector.dart';

/// Every relationship edge found for one newly-processed [FinancialEvent] —
/// the Part 16 "event graph" local neighborhood: at most one obligation
/// settlement edge, at most one transfer-pair edge, and exactly one
/// generic event-to-event relationship (`newEvent` when nothing else
/// applies). A caller persists whichever of these are non-null/actionable;
/// this class itself never writes anything.
class EventLinkingResult {
  const EventLinkingResult({
    required this.eventRelationship,
    this.obligationSettlement,
    this.transfer,
  });

  final EventRelationship eventRelationship;
  final EventRelationship? obligationSettlement;
  final EventRelationship? transfer;
}

/// The single entry point Phase 5 exposes: runs a new [FinancialEvent]
/// through every applicable relationship check and returns the combined
/// [EventLinkingResult]. Composition only — [EventRelationshipEngine],
/// [ObligationSettlementBridge], and [TransferPairDetector] each stay
/// independently usable and testable; this class just sequences them the
/// way a real caller (a future integration point, not built in this phase)
/// would.
class EventLinkingCoordinator {
  const EventLinkingCoordinator({
    required this.engine,
    this.settlementBridge,
    this.transferDetector,
  });

  final EventRelationshipEngine engine;
  final ObligationSettlementBridge? settlementBridge;
  final TransferPairDetector? transferDetector;

  Future<EventLinkingResult> link({
    required FinancialEvent candidate,
    required String relationshipId,
    String? settlementId,
    String? transferId,
  }) async {
    EventRelationship? transfer;
    if (candidate.isOwnAccountTransfer && transferDetector != null) {
      transfer = await transferDetector!.detect(
        candidate: candidate,
        id: transferId ?? '$relationshipId-transfer',
      );
    }

    EventRelationship? settlement;
    if (settlementBridge != null) {
      settlement = await settlementBridge!.settle(
        candidate: candidate,
        id: settlementId ?? '$relationshipId-settlement',
      );
    }

    final relationship = await engine.evaluate(
      candidate: candidate,
      id: relationshipId,
    );

    return EventLinkingResult(
      eventRelationship: relationship,
      obligationSettlement: settlement,
      transfer: transfer,
    );
  }
}
